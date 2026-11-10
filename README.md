# Manter Ativo

Painel nativo da barra de menus para o Mac. Uma frase diz o que a máquina está fazendo. A vigília continua valendo depois que o app fecha.

Feito em SwiftUI, para macOS 15 ou mais novo. Sem conta, sem nuvem, sem telemetria.

![Painel Agora](docs/painel.png)

## O que ele mostra

- CPU dos clusters Super e Performance, memória, swap, pressão e térmico.
- Bateria, ciclos, saúde e se o sistema segurou a carga.
- Apps agrupados, com busca. Encerrar pede confirmação. Forçar é um segundo passo.
- Disco, só quando você pede para medir. Apagar pede de novo e só mexe no que está no catálogo.
- Telas, USB, quem está segurando o sono, Spotlight e Wake-on-LAN.

Mesa e Bolso são sugestões. O app não troca o posto sozinho.

## Vigília

Dois níveis.

**Tela** segura a tela acesa. A tampa ainda pode dormir.

**Máquina** desliga o sono do sistema. Fechar a janela ou sair do app não desfaz isso. Quem segura é o agente `com.guicunha.keepawake`.

**Desligada** devolve o comportamento de antes. Na bateria, o sono volta. Na tomada, sono e telas permanecem em 0, que é o estado em que muita mesa já estava.

## Instalar

É preciso o Swift 6, que vem com o Xcode.

```bash
git clone https://github.com/guicunhaa/manter-ativo.git
cd manter-ativo
./script/build_and_run.sh --install
```

Isso coloca o app em `/Applications/Manter Ativo.app` e abre o painel. Se já existir um Manter Ativo ali, ele vai para `Manter Ativo (anterior).app` uma única vez.

Outros modos:

```bash
./script/build_and_run.sh            # só a barra de menus
./script/build_and_run.sh --cockpit  # abre o painel
swift test
```

O ícone fonte é `Icon/AppIcon.png`, quadrado e sangrado. O macOS aplica o arredondado.

## Nomes da sua máquina

Servidores MCP conhecidos já entram com nome. O que for só seu fica em `~/Library/Application Support/Manter Ativo/agentes.json`, fora do Git. Cada item tem `match` (trechos do comando), `title` e `key`.

## Retrato para a próxima sessão

Com o app aberto, ele grava `estado.md` e `estado.json` na pasta do projeto quando ele está em `~/Developer/Manter Ativo`. O texto não leva caminho de arquivo. O contrato está em [HARNESS.md](HARNESS.md).

## O que ele não finge

- Não há slider de ventoinha. Se o Mac não entrega RPM, o painel mostra a pressão térmica e o modo de energia.
- Não apaga Mail, Fotos, Mensagens nem a pasta de um projeto.
- Não encerra processo do sistema, a própria vigília, nem o harness do teclado e do mouse.
- O cache de pré-visualização do After Effects, quando aparece, é regenerável. Não é o projeto.

## Licença

[MIT](LICENSE). Pode usar, modificar e embarcar. O aviso de copyright fica junto.
