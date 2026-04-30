FROM ghcr.io/open-webui/open-webui@sha256:c2e4723fdbca5de8f9f0529e22b78acf5bc312a88da730bed88860063d028fe8

COPY patch_file_context.py /tmp/patch_file_context.py
RUN python /tmp/patch_file_context.py && rm /tmp/patch_file_context.py
