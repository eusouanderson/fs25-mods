# Server Auction House — FS25

## 🇧🇷 Português

**Server Auction House** (Leilão do Servidor) é um mod de **leilão multiplayer**
para **Farming Simulator 25** que permite aos jogadores leiloarem veículos,
equipamentos e recursos entre si em tempo real. Inspirado na arquitetura do
Server Journal, ele traz uma UI estilo GIANTS Engine com lances, cronômetro
regressivo e transferência automática de veículos e dinheiro.

### Funcionalidades
- Leilões em tempo real sincronizados entre todos os jogadores
- Criação de leilão com seleção de veículo, preço inicial e duração
- Sistema de lances com incremento mínimo de $1.000
- Validação de fundos e propriedade dos veículos
- Transferência automática de veículo e dinheiro ao final
- Cronômetro regressivo visível na interface
- Comandos de chat: `/auction start`, `/auction cancel`, `/bid`
- Persistência no savegame (`server_auctions.xml`)
- Interface gráfica nativa com abas de detalhes e formulário de criação

### Como usar
1. Pressione a tecla **L** (padrão) para abrir o Leilão do Servidor
2. Veja os leilões ativos na lista à esquerda
3. Selecione um item para ver detalhes (vendedor, lances, tempo restante)
4. Digite seu lance e clique **"Dar Lance"**
5. Para criar um leilão, clique **"Criar Leilão"**, selecione o veículo, defina
   preço inicial e duração, depois confirme
6. Ao final do tempo, o maior lance vence — veículo e dinheiro são transferidos

### Comandos de Chat
| Comando | Descrição |
|---------|-----------|
| `/auction start <id> <preco> <min>` | Iniciar leilão |
| `/auction cancel` | Cancelar seu leilão ativo |
| `/bid <valor>` | Dar lance no leilão ativo |

### Estrutura do mod
| Arquivo | Função |
|---------|--------|
| `ServerAuctionHouse.lua` | Lógica principal, servidor, save/load |
| `AuctionHouseUI.lua` | Controlador da interface gráfica |
| `NewAuctionEvent.lua` | Evento de rede: criar leilão |
| `PlaceBidEvent.lua` | Evento de rede: dar lance |
| `SyncAuctionsEvent.lua` | Evento de rede: sincronizar leilões |
| `AuctionHouseUI.xml` | Layout da interface |
| `profiles.xml` | Estilos de texto e cores |
| `views.xml` | Registro da view da UI |

### Instalação
1. Copie a pasta `FS25_ServerAuctionHouse` para
   `Documentos/My Games/FarmingSimulator2025/mods/`
2. Ative o mod no menu de mods do jogo/servidor

**Autor:** Antigravity | **Versão:** 1.0.0.0

---

## 🇺🇸 English

**Server Auction House** is a **multiplayer auction** mod for
**Farming Simulator 25** that lets players auction vehicles, equipment,
and farm resources to each other in real time. Inspired by the Server Journal
architecture, it features a native GIANTS Engine UI with bidding, countdown
timers, and automatic vehicle/money transfer.

### Features
- Real-time auctions synced across all players
- Auction creation with vehicle selection, starting price, and duration
- Bidding system with $1,000 minimum increment
- Fund and vehicle ownership validation
- Automatic vehicle and money transfer on completion
- Real-time countdown timer in the UI
- Chat commands: `/auction start`, `/auction cancel`, `/bid`
- Savegame persistence (`server_auctions.xml`)
- Native GUI with detail panel and creation form

### How to use
1. Press **L** (default) to open the Server Auction House
2. View active auctions in the list on the left
3. Select an item to see details (seller, bids, time left)
4. Enter your bid and click **"Place Bid"**
5. To create an auction, click **"Create Auction"**, select the vehicle,
   set starting price and duration, then confirm
6. When time runs out, the highest bid wins — vehicle and money are transferred

### Chat Commands
| Command | Description |
|---------|-------------|
| `/auction start <id> <price> <min>` | Start an auction |
| `/auction cancel` | Cancel your active auction |
| `/bid <amount>` | Place a bid on the active auction |

### Mod Structure
| File | Purpose |
|------|---------|
| `ServerAuctionHouse.lua` | Main logic, server, save/load |
| `AuctionHouseUI.lua` | GUI controller |
| `NewAuctionEvent.lua` | Network event: create auction |
| `PlaceBidEvent.lua` | Network event: place bid |
| `SyncAuctionsEvent.lua` | Network event: sync auctions |
| `AuctionHouseUI.xml` | GUI layout |
| `profiles.xml` | Text styles and colors |
| `views.xml` | UI view registration |

### Installation
1. Copy the `FS25_ServerAuctionHouse` folder to
   `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable the mod in the game/server mod menu

**Author:** Antigravity | **Version:** 1.0.0.0
