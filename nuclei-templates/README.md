# nuclei-templates/ — seus templates nuclei próprios

Coloque aqui templates `.yaml` autorais (padrões que você descobriu e quer reusar entre
programas). Rode com:

```bash
nuclei -l loot/<prog>/live-urls.txt -t nuclei-templates/ -o loot/<prog>/nuclei-custom.txt
```

O conteúdo (exceto este README) é git-ignored — templates podem conter payloads/paths sensíveis.
