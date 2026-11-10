# Harness

O app mantém um retrato da máquina para a próxima sessão de trabalho. Dois arquivos, reescritos no átomo, no máximo a cada 5 segundos, também com a janela fechada:

- `estado.md` — leitura em português
- `estado.json` — o mesmo retrato

## Onde fica

1. A pasta em `MANTER_ATIVO_STATE`, se essa variável existir.
2. `~/Developer/Manter Ativo/var/`, se o projeto estiver clonado ali.
3. `~/Library/Application Support/Manter Ativo/`, nos outros casos.

`var/` não entra no Git.

## Como ler

1. Leia `estado.md` antes de sondar a máquina de novo.
2. Confie na hora em "Atualizado". Se tiver mais de alguns minutos, o app não está rodando.
3. Use os títulos como estão. O arquivo não traz caminho, comando nem PID.
4. Vigília "Máquina" significa que o agente `com.guicunha.keepawake` está segurando o sono. Sair do app não desliga isso.
5. O arquivo descreve. Apagar, encerrar e mudar vigília, energia, Spotlight ou Wake-on-LAN fica no painel, com confirmação.

## O que entra

Frase do momento, CPU, memória, swap, pressão, térmico, bateria, telas, nomes USB, quem segura o sono, as doze famílias mais pesadas, agentes repetidos, perfil sugerido e Spotlight.

## O que fica de fora

Caminho de projeto, linha de comando, PID, Mail, Fotos, Mensagens e cache que ninguém pediu para medir.
