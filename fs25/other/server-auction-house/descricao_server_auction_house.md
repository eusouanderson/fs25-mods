# Server Auction House — FS25

**Versão:** 1.2.1 | **Autor:** B.O.B | **Categoria:** Gameplay / HUD

---

## 🇧🇷 Português

**Server Auction House** (Leilão do Servidor) é um mod de **leilão multiplayer**
para **Farming Simulator 25** que permite aos jogadores leiloarem veículos
entre si em tempo real. Inclui um sistema de bots que movimenta o mercado
criando leilões e dando lances automaticamente.

### Funcionalidades
- Leilões em tempo real sincronizados entre todos os jogadores
- Criação de leilão com seleção de veículo, preço inicial e duração
- Sistema de lances com incremento mínimo de $1.000
- Validação de fundos e propriedade dos veículos
- Transferência automática de veículo e dinheiro ao final
- Cronômetro regressivo visível na interface
- **Sistema de bots**: 8 bots com 4 perfis de comportamento (Conservador, Competitivo, Agressivo, Aleatório)
- Configuração de bots pelo menu **Configurações > Server Auction House** (apenas servidor)
- Persistência no savegame (`server_auctions.xml`)
- Interface gráfica nativa integrada ao menu do jogo

### Como usar
1. Pressione a tecla **L** (padrão) — ou configure em *Opções > Controles*
2. Veja os leilões ativos na lista à esquerda
3. Selecione um item para ver detalhes (vendedor, lances, tempo restante)
4. Digite seu lance e clique **"Dar Lance"**
5. Para criar um leilão, clique **"Criar Leilão"**, selecione o veículo, defina
   preço inicial e duração, depois confirme
6. Ao final do tempo, o maior lance vence — veículo e dinheiro são transferidos

### Sistema de Bots
O mod inclui 8 bots com 4 perfis de comportamento que participam ativamente do mercado:

| Perfil | Comportamento |
|--------|--------------|
| **Conservador** | Dá lances baixos (5-15% acima), raramente entra em disputa |
| **Competitivo** | Lances moderados (10-25% acima), disputa ativamente |
| **Agressivo** | Lances altos (20-40% acima), entra em guerra de lances |
| **Aleatório** | Comportamento imprevisível, mistura todos os perfis |

Os bots criam automaticamente até 3 leilões simultâneos com duração entre 3-15 minutos.
É possível desativar os bots pelo menu de configurações do jogo.

### Itens ganhos de bots
Ao vencer um leilão de bot, o veículo é spawnado na loja do mapa
(shop spawn area). **Nota:** o spawn diretamente sobre o jogador será
implementado em uma versão futura.

### Instalação
1. Copie a pasta `FS25_ServerAuctionHouse` para
   `Documentos/My Games/FarmingSimulator2025/mods/`
2. Ative o mod no menu de mods do jogo/servidor

---

## 🇺🇸 English

**Server Auction House** is a **multiplayer auction** mod for
**Farming Simulator 25** that lets players auction vehicles in real time.
Includes an AI bot system that drives market activity by creating auctions
and placing bids automatically.

### Features
- Real-time auctions synced across all players
- Auction creation with vehicle selection, starting price, and duration
- Bidding system with $1,000 minimum increment
- Fund and vehicle ownership validation
- Automatic vehicle and money transfer on completion
- Real-time countdown timer in the UI
- **Bot system**: 8 bots with 4 behavior profiles (Conservative, Competitive, Aggressive, Random)
- Bot configuration via **Settings > Server Auction House** (server only)
- Savegame persistence (`server_auctions.xml`)
- Native GUI integrated into the in-game menu

### How to use
1. Press **L** (default) — configurable in *Options > Controls*
2. View active auctions in the list on the left
3. Select an item to see details (seller, bids, time left)
4. Enter your bid and click **"Place Bid"**
5. To create an auction, click **"Create Auction"**, select the vehicle,
   set starting price and duration, then confirm
6. When time runs out, the highest bid wins — vehicle and money are transferred

### Bot System
The mod includes 8 bots with 4 behavior profiles:

| Profile | Behavior |
|---------|----------|
| **Conservative** | Low bids (5-15% over), rarely contests |
| **Competitive** | Moderate bids (10-25% over), actively contests |
| **Aggressive** | High bids (20-40% over), engages in bidding wars |
| **Random** | Unpredictable, mixes all profiles |

Bots automatically create up to 3 concurrent auctions with 3-15 minute durations.
Bots can be disabled via the in-game settings menu.

### Items won from bots
When you win a bot auction, the vehicle spawns at the map's shop spawn area.
**Note:** spawning directly on the player's location will be implemented in a future version.

### Installation
1. Copy the `FS25_ServerAuctionHouse` folder to
   `Documents/My Games/FarmingSimulator2025/mods/`
2. Enable the mod in the game/server mod menu
