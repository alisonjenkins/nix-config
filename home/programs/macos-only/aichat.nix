{ ... }: {
  # aichat configured to talk to the local llama-swap endpoint
  # (modules.llamaSwap, served at 127.0.0.1:8080). The model names below must
  # match the keys under modules.llamaSwap.models in the host config.
  #
  # Usage in scripts:
  #   aichat "summarise this" < file.txt
  #   aichat -m local:qwen3-32b "harder reasoning task"
  # Or hit the raw OpenAI-compatible endpoint at http://127.0.0.1:8080/v1.
  xdg.configFile."aichat/config.yaml".text = ''
    model: local:qwen3-coder
    save: false
    clients:
      - type: openai-compatible
        name: local
        api_base: http://127.0.0.1:8080/v1
        api_key: sk-no-key-required
        models:
          - name: qwen3-coder
            max_input_tokens: 32768
            supports_function_calling: true
          - name: qwen3-32b
            max_input_tokens: 32768
            supports_function_calling: true
  '';
}
