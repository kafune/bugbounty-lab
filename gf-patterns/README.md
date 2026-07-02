# gf-patterns/ — seus padrões gf próprios

Padrões `.json` do [gf](https://github.com/tomnomnom/gf) para garimpar `loot/<prog>/urls.txt`
por classe (ssrf, redirect, sqli, ssti...). Aponte o gf pra cá:

```bash
export GF_PATTERNS="$PWD/gf-patterns"
gf ssrf < loot/<prog>/urls.txt
```

Conteúdo (exceto este README) é git-ignored.
