# Server Auction House (Leilão do Servidor) — Farming Simulator 25 Mod

[English Version](#english-description) | [Versão em Português](#descricao-em-portugues)

---

## English Description

**Server Auction House** is a real-time multiplayer auction system for **Farming Simulator 25**. It allows players to buy and sell their own vehicles and equipment dynamically, creating an integrated second-hand market within the server.

All operations are server-authoritative, ensuring security and full state persistence in the savegame.

### 🎮 Controls & Gameplay
* **Open the Auction Panel:** Press the **`K`** key on your keyboard.
* **Creating an Auction (Selling):** 
  1. Open the panel and click **Create Auction**.
  2. Select any eligible vehicle or tool owned or leased by your farm.
  3. Set a starting bid and the auction duration in minutes.
  4. Confirm the listing. The item will be placed in the auction house and removed from your farm.
* **Bidding on Auctions (Buying):**
  1. Select an active auction to see details (seller, starting bid, current bid, highest bidder, remaining time, and store image).
  2. The input field automatically suggests the next minimum bid.
  3. Click **Place Bid** to participate.

> [!WARNING]
> **Cancellation Rule:** To ensure a fair marketplace, sellers **cannot cancel** an auction once it has received at least one bid.

### ⚙️ Server Configuration
Admin players can toggle the **Virtual Bot System** in the game's general settings:
* **ON:** Simulated AI bots will dynamically create auctions for base game equipment and place bids on player-listed items.
* **OFF:** The auction house functions strictly between real players on the server.

### ⚠️ Important Note
* **Item Spawning:** Won vehicles/items currently spawn directly at the player character's coordinates. This is a temporary behavior and will be resolved in a future update to spawn items at the shop delivery zone.

---

## Descrição em Português

O **Server Auction House** é um sistema de leilão multiplayer em tempo real para o **Farming Simulator 25**. Ele permite que os jogadores comprem e vendam seus próprios veículos e implementos de forma dinâmica, criando um mercado de usados integrado dentro do servidor.

Toda a lógica é processada no servidor (*server-authoritative*), garantindo segurança e persistência total do estado dos leilões no savegame.

### 🎮 Controles e Gameplay
* **Abrir o Painel de Leilões:** Pressione a tecla **`K`** no teclado.
* **Criar um Leilão (Venda):** 
  1. Abra o painel e clique em **Criar Leilão**.
  2. Selecione qualquer veículo ou ferramenta elegível de propriedade ou arrendamento da sua fazenda.
  3. Defina um lance inicial e a duração do leilão em minutos.
  4. Confirme a listagem. O item será anunciado na casa de leilões e removido da sua fazenda.
* **Dar Lances em Leilões (Compra):**
  1. Selecione um leilão ativo para ver detalhes (vendedor, lance inicial, lance atual, maior licitante, tempo restante e imagem oficial do item).
  2. O campo de entrada sugere automaticamente o valor do próximo lance mínimo.
  3. Clique em **Dar Lance** para registrar sua oferta.

> [!WARNING]
> **Regra de Cancelamento:** Para garantir um mercado justo, o vendedor **não pode cancelar** um leilão após ele ter recebido pelo menos um lance válido.

### ⚙️ Configuração do Servidor
Administradores podem controlar o **Sistema de Bots Virtuais** no menu de configurações gerais do jogo:
* **Ligado (ON):** Bots da Inteligência Artificial criam leilões de itens do jogo base e dão lances competitivos em itens listados pelos jogadores.
* **Desligado (OFF):** A casa de leilões funcionará exclusivamente entre os jogadores reais do servidor.

### ⚠️ Observação Importante
* **Entrega de Itens Ganhos:** Veículos e itens arrematados atualmente aparecem (spawnam) diretamente nas coordenadas em que o seu personagem estiver de pé. Esta é uma limitação temporária e será resolvida em uma atualização futura para que os itens apareçam na zona de entrega da loja de máquinas.
