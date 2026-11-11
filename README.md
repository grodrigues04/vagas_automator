# vagas_automator

Rotina semanal que roda o Claude Code toda **quinta-feira às 21h** para buscar vagas, gera um
relatório em PDF e envia pelo WhatsApp usando a
[interface-personal-whats](https://github.com/grodrigues04/interface-personal-whats) (o envio
em si é feito pelo projeto personalWhats).

## Como funciona

- `runner/scheduler.sh` olha o relógio a cada 30s. Na janela de quinta 21:00–21:09 roda
  `run.sh`; se o computador estiver desligado ou suspenso nessa janela, a semana é perdida (não
  há recuperação em outro dia).
- `runner/run.sh` faz uma tentativa por semana ISO (lock em `data/state/`), roda o Claude com
  `data/prompt.txt`, `data/curriculo.pdf` e a memória `data/memoria/vagas-vistas.json`, e grava
  o resultado em `data/out/<data>/` com `PRONTO` (sucesso) ou `CANCELADO` (motivo da falha).
- `runner/send_results.py` (a cada 30s) envia cada pasta com `PRONTO`/`CANCELADO` pela interface
  e grava `ENVIADO` com o id da mensagem. Conteúdo recusado pela interface (ex.: PDF acima de
  10MB) gera `ENVIO_FALHOU` e um aviso em texto.

## Segurança

O Claude lê páginas de vagas que podem conter prompt injection. O container começa como root,
com a URI do MongoDB e a senha de criptografia; `run-as-claude-user.sh` faz todo script que roda
o Claude se executar de novo como o usuário `node`, com ambiente limpo (só o token do Claude).
Assim o Claude não tem acesso às credenciais do personalWhats, nem via `docker exec`.

## Configuração

```bash
cp .env.example .env   # token do Claude, MONGO_URI, ENCRYPTION_PASSWORD, VAGAS_RECIPIENT
docker compose up -d --build
```

`VAGAS_RECIPIENT` vazio envia para o contato padrão do personalWhats.

## Comandos úteis

```bash
# Teste rápido da cadeia (Claude, PDF, envio), sem mexer na memória nem no lock da semana
docker exec vagas-automator /app/smoke-test.sh

# Rodar a rotina completa agora, sem afetar a rotina de quinta
docker exec -e MANUAL_RUN=1 vagas-automator /app/run.sh

# Nova versão da interface
docker compose build --no-cache && docker compose up -d
```

## Arquivos que não vão para o git

O repositório é público, então os dados pessoais da candidata ficam só na máquina:
`data/prompt.txt`, `data/curriculo.pdf`, `data/memoria/vagas-vistas.json` e `result-example/`.
Faça backup deles fora do git.
