"""
title: Image Gen (Persistent + VRAM Unload)
author: Haervwe (Modified)
version: 0.5.0
required_open_webui_version: 0.11.0
"""

import asyncio
import aiohttp
import json

from fastapi import Request
from pydantic import BaseModel, Field
from typing import Any, Callable, Optional, Dict, List

from open_webui.routers.images import image_generations, GenerateImageForm
from open_webui.models.users import Users
from open_webui.models.chats import Chats
from open_webui.utils.chat_id import is_saved_chat_id


async def get_loaded_models_async(
    api_url: str = "http://localhost:11434",
) -> List[Dict[str, Any]]:
    """Get all currently loaded Ollama models."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{api_url.rstrip('/')}/api/ps") as response:
                if response.status != 200:
                    return []

                data = await response.json()
                return data.get("models", [])

    except Exception as e:
        print(f"Error fetching loaded models: {e}")
        return []


async def unload_all_models_async(
    api_url: str = "http://localhost:11434",
) -> bool:
    """Unload all currently loaded Ollama models from VRAM."""
    try:
        loaded_models = await get_loaded_models_async(api_url)

        if not loaded_models:
            return True

        async with aiohttp.ClientSession() as session:
            for model in loaded_models:
                if isinstance(model, dict):
                    model_name = model.get("name", model.get("model", ""))
                else:
                    model_name = str(model)

                if not model_name:
                    continue

                payload: Dict[str, Any] = {
                    "model": model_name,
                    "keep_alive": 0,
                }

                try:
                    async with session.post(
                        f"{api_url.rstrip('/')}/api/generate",
                        json=payload,
                    ) as response:
                        # Ollama performs the unload; response body is not needed.
                        pass
                except Exception as e:
                    print(f"Error unloading Ollama model " f"{model_name}: {e}")

        return True

    except Exception as e:
        print(f"Error unloading models: {e}")
        return False


async def get_loaded_llamacpp_models_async(
    api_url: str = "http://ainode-ollama:8080",
) -> List[Dict[str, Any]]:
    """Get the llama.cpp router models that are currently loaded."""
    try:
        timeout = aiohttp.ClientTimeout(total=30)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(f"{api_url.rstrip('/')}/models") as response:
                if response.status != 200:
                    return []

                data = await response.json()

                loaded = []
                for model in data.get("data", []):
                    if not isinstance(model, dict):
                        continue

                    # Router builds report loaded/loading/unloaded/failed in
                    # status.value. If a build does not report status at all,
                    # treat the entry as loaded and let the unload call decide.
                    status = model.get("status")
                    if isinstance(status, dict):
                        if status.get("value") != "loaded":
                            continue

                    loaded.append(model)

                return loaded

    except Exception as e:
        print(f"Error fetching loaded llama.cpp models: {e}")
        return []


async def unload_all_llamacpp_models_async(
    api_url: str = "http://ainode-ollama:8080",
) -> int:
    """Unload all currently loaded llama.cpp router models from VRAM.

    Returns the number of models that were unloaded.
    """
    try:
        loaded_models = await get_loaded_llamacpp_models_async(api_url)

        if not loaded_models:
            return 0

        unloaded_count = 0
        timeout = aiohttp.ClientTimeout(total=30)

        async with aiohttp.ClientSession(timeout=timeout) as session:
            for model in loaded_models:
                model_name = model.get("id", model.get("model", ""))

                if not model_name:
                    continue

                payload: Dict[str, Any] = {
                    "model": model_name,
                }

                try:
                    async with session.post(
                        f"{api_url.rstrip('/')}/models/unload",
                        json=payload,
                    ) as response:
                        # The router terminates the model's child process;
                        # the response body is not needed on success.
                        if response.status == 200:
                            unloaded_count += 1
                        else:
                            body = await response.text()
                            print(
                                "Error unloading llama.cpp model "
                                f"{model_name}: HTTP {response.status} {body}"
                            )
                except Exception as e:
                    print(
                        f"Error unloading llama.cpp model " f"{model_name}: {e}"
                    )

        return unloaded_count

    except Exception as e:
        print(f"Error unloading llama.cpp models: {e}")
        return 0


async def get_comfyui_free_vram_async(
    session: aiohttp.ClientSession,
    api_url: str,
) -> Optional[int]:
    """Return the smallest free-VRAM value ComfyUI reports, in bytes."""
    try:
        async with session.get(f"{api_url}/system_stats") as response:
            if response.status != 200:
                return None

            data = await response.json()

    except Exception:
        return None

    free_values = []
    for device in data.get("devices", []):
        if not isinstance(device, dict):
            continue

        value = device.get("vram_free")
        if isinstance(value, (int, float)):
            free_values.append(int(value))

    return min(free_values) if free_values else None


async def free_comfyui_memory_async(
    api_url: str = "http://ainode-comfyui:8188",
    wait_timeout: float = 10.0,
) -> bool:
    """Unload ComfyUI's models and release its cached VRAM.

    ComfyUI's /free endpoint only sets flags on its prompt queue; the worker
    thread performs the actual unload on its next loop iteration. A 200
    response therefore does not mean the VRAM is free yet. Poll system_stats
    until the reported free VRAM stops growing, so the caller can be sure the
    memory is available before the LLM tries to reload.

    Never raises: a failure here must not break image generation.
    """
    base = api_url.rstrip("/")
    timeout = aiohttp.ClientTimeout(total=wait_timeout + 10)

    try:
        async with aiohttp.ClientSession(timeout=timeout) as session:
            baseline = await get_comfyui_free_vram_async(session, base)

            async with session.post(
                f"{base}/free",
                json={
                    "unload_models": True,
                    "free_memory": True,
                },
            ) as response:
                if response.status != 200:
                    body = await response.text()
                    print(
                        "Error freeing ComfyUI memory: "
                        f"HTTP {response.status} {body}"
                    )
                    return False

            if baseline is None:
                return True

            # Wait until three consecutive samples show no meaningful growth.
            # 64 MiB of tolerance absorbs driver bookkeeping noise; three
            # samples give ComfyUI's worker time to pick up the flag before
            # we accept "nothing changed" as done.
            previous = baseline
            quiet_samples = 0
            loop = asyncio.get_running_loop()
            deadline = loop.time() + wait_timeout

            while loop.time() < deadline:
                await asyncio.sleep(0.5)

                current = await get_comfyui_free_vram_async(session, base)
                if current is None:
                    break

                if current - previous < 64 * 1024 * 1024:
                    quiet_samples += 1
                    if quiet_samples >= 3:
                        return True
                else:
                    quiet_samples = 0

                previous = current

            return True

    except Exception as e:
        print(f"Error freeing ComfyUI memory: {e}")
        return False


class Tools:
    class Valves(BaseModel):
        unload_ollama_models: bool = Field(
            default=True,
            description=(
                "Unload all Ollama models before calling the configured "
                "Open WebUI image generator."
            ),
        )

        ollama_url: str = Field(
            default="http://ainode-ollama:11434",
            description=(
                "Ollama API URL. Use the Docker service hostname "
                "when Open WebUI and Ollama are in separate containers."
            ),
        )

        vram_unload_delay: float = Field(
            default=2.5,
            description=(
                "Seconds to wait after unloading models so "
                "ROCm can release their VRAM before image generation."
            ),
        )

        unload_llamacpp_models: bool = Field(
            default=True,
            description=(
                "Unload all llama.cpp router models (such as Bonsai2 Qwen) "
                "before calling the configured Open WebUI image generator."
            ),
        )

        llamacpp_url: str = Field(
            default="http://ainode-ollama:8080",
            description=(
                "llama.cpp router API URL, without the /v1 suffix. Use the "
                "Docker service hostname when Open WebUI and llama.cpp are "
                "in separate containers."
            ),
        )

        free_comfyui_after_generation: bool = Field(
            default=True,
            description=(
                "Ask ComfyUI to unload its models and release its VRAM after "
                "generating. Without this, ComfyUI keeps enough VRAM that "
                "large llama.cpp models (Bonsai2 Qwen) fail to reload."
            ),
        )

        comfyui_url: str = Field(
            default="http://ainode-comfyui:8188",
            description=(
                "ComfyUI API URL, without the /v1 suffix. Use the Docker "
                "service hostname when Open WebUI and ComfyUI are in "
                "separate containers."
            ),
        )

    def __init__(self):
        self.valves = self.Valves()

    async def _release_comfyui_vram_async(
        self,
        __event_emitter__: Optional[Callable[[Dict[str, Any]], Any]] = None,
    ) -> None:
        """Free ComfyUI's VRAM so the chat LLM can reload afterwards."""
        if not self.valves.free_comfyui_after_generation:
            return

        if __event_emitter__:
            try:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "Releasing ComfyUI VRAM...",
                            "done": False,
                        },
                    }
                )
            except Exception:
                pass

        await free_comfyui_memory_async(api_url=self.valves.comfyui_url)

    async def generate_image(
        self,
        prompt: str,
        model: str | None = None,
        __request__: Request | None = None,
        __user__: dict[str, Any] | None = None,
        __event_emitter__: Optional[Callable[[Dict[str, Any]], Any]] = None,
        __chat_id__: str | None = None,
        __message_id__: str | None = None,
    ) -> str:
        """
        Generate an image and display it in-line with current chat. Unloads ollama (you) or llama.cpp (Bonsai2 Qwen) from VRAM first, releases ComfyUI's VRAM afterwards so your model can load back in when finished.
        Your prompt should specify "anime style" unless another style like photorealistic is requested.
        Use "Image generation guidelines" in your knowlege library unless just adjusting a previously used prompt.
        """

        # ============================================================
        # 1. Unload Ollama
        # ============================================================
        if self.valves.unload_ollama_models:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "Unloading LLM from VRAM...",
                            "done": False,
                        },
                    }
                )

            await unload_all_models_async(api_url=self.valves.ollama_url)

            await asyncio.sleep(self.valves.vram_unload_delay)

        # ============================================================
        # 1b. Unload llama.cpp router models (Bonsai2 Qwen)
        # ============================================================
        if self.valves.unload_llamacpp_models:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": (
                                "Unloading Bonsai2 (llama.cpp) from VRAM..."
                            ),
                            "done": False,
                        },
                    }
                )

            unloaded_count = await unload_all_llamacpp_models_async(
                api_url=self.valves.llamacpp_url
            )

            if unloaded_count:
                # /models/unload returns before the model's child process has
                # fully exited, so give ROCm a moment to release VRAM.
                await asyncio.sleep(self.valves.vram_unload_delay)

        # ============================================================
        # 2. Generation status
        # ============================================================
        if __event_emitter__:
            await __event_emitter__(
                {
                    "type": "status",
                    "data": {
                        "description": "Generating image in ComfyUI...",
                        "done": False,
                    },
                }
            )

        try:
            # ========================================================
            # 3. Use Open WebUI's configured image-generation backend
            # ========================================================
            if model and __request__ is not None:
                __request__.app.state.config.IMAGE_GENERATION_MODEL = model

            user = None

            if __user__ and __user__.get("id"):
                user = await Users.get_user_by_id(__user__["id"])

            images = await image_generations(
                request=__request__,
                form_data=GenerateImageForm(
                    prompt=prompt,
                    model=model,
                ),
                user=user,
            )

            # ========================================================
            # 4. Create Open WebUI image-file entries
            #
            # This intentionally mirrors native Open WebUI 0.11.0:
            #
            #     {'type': 'image', 'url': img['url']}
            # ========================================================
            image_files = [
                {
                    "type": "image",
                    "url": image["url"],
                }
                for image in images
                if isinstance(image, dict) and image.get("url")
            ]

            # ========================================================
            # 5. PERSIST THE IMAGE TO THE CHAT DATABASE
            #
            # This is the critical part that your previous version
            # was missing.
            #
            # Native Open WebUI 0.11.0 does the same thing.
            # ========================================================
            if is_saved_chat_id(__chat_id__) and __message_id__ and image_files:
                db_files = await Chats.add_message_files_by_id_and_message_id(
                    __chat_id__,
                    __message_id__,
                    image_files,
                )

                if db_files is not None:
                    image_files = db_files

            # ========================================================
            # 6. Push the persisted image to the frontend
            # ========================================================
            if __event_emitter__ and image_files:
                await __event_emitter__(
                    {
                        "type": "chat:message:files",
                        "data": {
                            "files": image_files,
                        },
                    }
                )

            # ========================================================
            # 7. Free ComfyUI's VRAM
            #
            # ComfyUI keeps its models resident after a generation,
            # which leaves too little VRAM for large llama.cpp models
            # (Bonsai2 Qwen) to load again. This must happen before
            # the tool returns, because the LLM reload starts as soon
            # as it gets control back.
            # ========================================================
            await self._release_comfyui_vram_async(__event_emitter__)

            # ========================================================
            # 8. Finish status
            # ========================================================
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "Image generation complete.",
                            "done": True,
                        },
                    }
                )

            # ========================================================
            # 9. Return a tool result specifically for the LLM
            #
            # The image itself is already displayed/persisted, so
            # don't put Markdown/image URLs into this response.
            #
            # The explicit wording helps prevent Qwen from treating
            # the tool result as a fresh copy of the user's request.
            # ========================================================
            if image_files:
                return json.dumps(
                    {
                        "status": "success",
                        "message": (
                            "IMAGE GENERATION TOOL COMPLETED SUCCESSFULLY. "
                            "The requested image has been generated and "
                            "saved to the current chat message and is already "
                            "visible to the user. "
                            "\n\n"
                            "IMPORTANT: The following tool result is a "
                            "confirmation of completion, NOT a new user "
                            "request and NOT a repeated prompt. "
                            "Do NOT invoke image generation again. "
                            "This is still the same turn, image generation has just handed it back to you after it finished"
                            "You may offer final comments but you should finish your turn soon"
                        ),
                        "images_generated": len(image_files),
                    },
                    ensure_ascii=False,
                )

            return json.dumps(
                {
                    "status": "success",
                    "message": (
                        "Image generation completed, but no image file "
                        "was returned by Open WebUI."
                    ),
                },
                ensure_ascii=False,
            )

        except Exception as e:
            # Release ComfyUI even when generation failed: it may still
            # be holding partially loaded models.
            await self._release_comfyui_vram_async(__event_emitter__)

            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": f"Image generation failed: {e}",
                            "done": True,
                        },
                    }
                )

            return json.dumps(
                {
                    "status": "error",
                    "error": str(e),
                },
                ensure_ascii=False,
            )
