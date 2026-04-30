from pathlib import Path


MIDDLEWARE = Path("/app/backend/open_webui/utils/middleware.py")

HELPER = r'''
from open_webui.models.files import Files
from open_webui.storage.provider import Storage
from open_webui.utils.access_control.files import has_access_to_file

SMALL_FILE_FULL_CONTEXT_EXTENSIONS = {
    "c",
    "cc",
    "conf",
    "cpp",
    "cs",
    "css",
    "csv",
    "go",
    "h",
    "hpp",
    "htm",
    "html",
    "ini",
    "java",
    "js",
    "json",
    "jsx",
    "log",
    "lua",
    "md",
    "php",
    "py",
    "rb",
    "rs",
    "sh",
    "sql",
    "toml",
    "ts",
    "tsx",
    "txt",
    "xml",
    "yaml",
    "yml",
}

SMALL_FILE_FULL_CONTEXT_MIME_TYPES = {
    "application/javascript",
    "application/json",
    "application/sql",
    "application/toml",
    "application/x-javascript",
    "application/x-ndjson",
    "application/x-sh",
    "application/x-yaml",
    "application/xml",
    "text/csv",
    "text/html",
    "text/markdown",
    "text/plain",
    "text/xml",
}


def _small_file_full_context_max_bytes() -> int:
    try:
        return int(os.environ.get("SMALL_FILE_FULL_CONTEXT_MAX_BYTES", "131072"))
    except ValueError:
        return 131072


def _coerce_file_size(value):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


def _get_file_item_value(item, *keys):
    if not isinstance(item, dict):
        return None

    for key in keys:
        value = item.get(key)
        if value not in (None, ""):
            return value

    for nested_key in ("meta", "metadata", "source"):
        nested = item.get(nested_key)
        if not isinstance(nested, dict):
            continue
        for key in keys:
            value = nested.get(key)
            if value not in (None, ""):
                return value
        nested_data = nested.get("data")
        if isinstance(nested_data, dict):
            for key in keys:
                value = nested_data.get(key)
                if value not in (None, ""):
                    return value

    return None


def _is_small_text_file_item(item) -> bool:
    if not isinstance(item, dict):
        return False

    if item.get("type") == "image":
        return False

    name = str(_get_file_item_value(item, "name", "filename", "file_name") or "").lower()
    extension = name.rsplit(".", 1)[-1] if "." in name else ""
    extension_is_text = extension in SMALL_FILE_FULL_CONTEXT_EXTENSIONS

    content_type = (_get_file_item_value(item, "content_type", "mime_type", "mime") or "").lower()
    if content_type.startswith(("audio/", "image/", "video/")) and not extension_is_text:
        return False

    size = _coerce_file_size(_get_file_item_value(item, "size", "file_size", "bytes"))
    max_bytes = _small_file_full_context_max_bytes()
    if max_bytes <= 0 or size is None or size > max_bytes:
        return False

    return (
        content_type.startswith("text/")
        or content_type in SMALL_FILE_FULL_CONTEXT_MIME_TYPES
        or extension_is_text
    )


def _should_use_full_context_for_small_text_files(files) -> bool:
    return bool(files) and all(_is_small_text_file_item(item) for item in files)


def _read_small_text_file_content(path: str, max_bytes: int):
    try:
        resolved = Storage.get_file(path)
        with open(resolved, "rb") as file:
            data = file.read(max_bytes + 1)
    except Exception:
        return None

    if len(data) > max_bytes or b"\x00" in data:
        return None

    for encoding in ("utf-8-sig", "utf-8"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue

    return None


async def _load_small_text_file_full_context(item, user):
    file_id = item.get("id")
    if item.get("type") != "file" or not file_id:
        return item

    file_object = await Files.get_file_by_id(file_id)
    if not file_object:
        return item

    if user is not None and not (
        user.role == "admin"
        or file_object.user_id == user.id
        or await has_access_to_file(file_id, "read", user)
    ):
        return item

    content = await asyncio.to_thread(
        _read_small_text_file_content,
        file_object.path,
        _small_file_full_context_max_bytes(),
    )
    if content is None:
        return item

    metadata = {}
    if isinstance(file_object.data, dict):
        metadata = file_object.data.get("metadata") or {}

    return {
        **item,
        "context": "full",
        "file": {
            "data": {
                "content": content,
                "metadata": metadata,
            },
            "meta": file_object.meta or {},
        },
    }


async def _promote_small_text_files_to_full_context(files, user):
    if not files:
        return files

    promoted = []
    for item in files:
        if _is_small_text_file_item(item):
            item = await _load_small_text_file_full_context(item, user)
        promoted.append(item)
    return promoted

'''


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise RuntimeError(f"Could not find expected middleware.py block:\n{old}")
    return text.replace(old, new, 1)


text = MIDDLEWARE.read_text()

if "SMALL_FILE_FULL_CONTEXT_EXTENSIONS" not in text:
    text = replace_once(
        text,
        "\n\nasync def chat_image_generation_handler(request: Request, form_data: dict, extra_params: dict, user):\n",
        HELPER
        + "\n\nasync def chat_image_generation_handler(request: Request, form_data: dict, extra_params: dict, user):\n",
    )

text = replace_once(
    text,
    "        # Check if all files are in full context mode\n"
    "        all_full_context = all(item.get('context') == 'full' for item in files)\n",
    "        # Check if all files are in full context mode, or auto-promote small text/code files.\n"
    "        all_full_context = all(item.get('context') == 'full' for item in files)\n"
    "        auto_full_context = _should_use_full_context_for_small_text_files(files)\n"
    "        if auto_full_context:\n"
    "            files = await _promote_small_text_files_to_full_context(files, user)\n"
    "            body['metadata']['files'] = files\n"
    "        use_full_context = all_full_context or auto_full_context\n",
)

text = replace_once(text, "        if not all_full_context:\n", "        if not use_full_context:\n")
text = replace_once(
    text,
    "                full_context=all_full_context or request.app.state.config.RAG_FULL_CONTEXT,\n",
    "                full_context=use_full_context or request.app.state.config.RAG_FULL_CONTEXT,\n",
)

MIDDLEWARE.write_text(text)
