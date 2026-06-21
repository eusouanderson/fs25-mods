# Documentação Técnica — Server Auction House (Bot System)

## Visão Geral

Implementação de um sistema de bots (NPCs) para o mod Server Auction House no Farming Simulator 25.
Os bots criam leilões automaticamente e dão lances em leilões de jogadores, simulando uma economia ativa no servidor.

---

## Arquivos Modificados / Criados

### `scripts/AuctionBotManager.lua` — NOVO
Gerencia toda a lógica dos bots: criação de leilões, decisão de lances, perfis de comportamento,
e spawn de veículos para jogadores.

### `scripts/AuctionManager.lua` — MODIFICADO
- `createBotAuction()` — novo método para criar leilões sem veículo físico (bots não têm veículo no mundo)
- `placeBid()` — bypass da verificação de saldo para bots (bots têm fundos ilimitados)
- `resolveAuction()` — agora trata 3 cenários:
  1. Bot vence leilão de jogador → veículo é deletado, jogador recebe o dinheiro
  2. Jogador vence leilão de bot → veículo é spawnado para o jogador, jogador paga
  3. Jogador vence leilão de jogador → transferência normal

### `scripts/AuctionStorage.lua` — MODIFICADO
- Adicionado `xmlFilename` e `storePrice` aos dados persistidos no savegame
- Leitura/escrita dos novos campos no XML do savegame

### `scripts/AuctionEvent.lua` — MODIFICADO
- Sincronização de `xmlFilename` e `storePrice` entre servidor e clientes via stream

### `scripts/main.lua` — MODIFICADO
- `onUpdate(_, dt)` — parâmetro `dt` corrigido (era `onUpdate(dt)` que recebia a mission table como `dt`)
- Chamada para `AuctionBotManager.update(dt)` adicionada no update

### `modDesc.xml` — MODIFICADO
- Ordem de carregamento corrigida: `AuctionBotManager.lua` carregado ANTES de `AuctionManager.lua`
  (necessário porque `AuctionManager:placeBid()` chama `AuctionBotManager.isBotId()`)

---

## Sistema de Bots

### 8 Bots, 4 Perfis

| ID    | Nome                     | Perfil        |
|-------|--------------------------|---------------|
| -100  | Pedro (Conservador)      | CONSERVATIVE  |
| -101  | Lucas (Competitivo)      | COMPETITIVE   |
| -102  | Carlos (Agressivo)       | AGGRESSIVE    |
| -103  | Mateus (Aleatório)       | RANDOM        |
| -104  | Júlia (Conservador)      | CONSERVATIVE  |
| -105  | Fernanda (Competitivo)   | COMPETITIVE   |
| -106  | Bruno (Agressivo)        | AGGRESSIVE    |
| -107  | Amanda (Aleatório)       | RANDOM        |

IDs negativos (< 0) para distinção fácil de jogadores reais via `isBotId()`.

### Comportamento dos Perfis

- **CONSERVATIVE**: Limite de 50-70% do valor de loja. Desiste cedo (para de dar lances com <30s restantes).
  Chance de lance: 15% por tick.
- **COMPETITIVE**: Limite de 80-105%. Ocasionalmente aumenta lance em 1-3k. Chance: 25%.
- **AGGRESSIVE**: Limite de 95-125%. Próximo do fim (<45s) chance sobe para 80%.
  Frequentemente aumenta lance em 2-8k extra.
- **RANDOM**: Limite de 40-115%. Chance imprevisível (0-40%). Aumento aleatório de 0-5k.

### Valuation (Precificação)

O limite máximo de cada bot é calculado com `math.randomseed(bot.id + auction.id)` garantindo
que um mesmo par bot-leilão sempre produza o mesmo valor (comportamento determinístico estável).
Após o cálculo, a semente é restaurada para `g_currentMission.time` para não afetar mecânicas do jogo.

### Criação de Leilões

- A cada 8 segundos (TICK_INTERVAL), o bot manager verifica se há menos de 3 leilões de bots ativos
- Se sim, 15% de chance (CREATE_CHANCE) de criar um novo leilão
- Item aleatório da loja (`g_storeManager:getItems()`), filtrando categorias irrelevantes
- Preço inicial: 50-85% do valor de loja
- Duração: 3-15 minutos aleatório

---

## Bugs Corrigidos

### 1. Ordem de Carregamento (`modDesc.xml`)
**Sintoma**: `AuctionBotManager` é nil quando `AuctionManager` tenta chamar `isBotId()`.
**Causa**: `AuctionManager.lua` carregado antes de `AuctionBotManager.lua`.
**Solução**: Reordenar `extraSourceFiles` — bot manager antes do manager.

### 2. Filtro de Store Items (`getRandomStoreItem`)
**Sintoma**: Nenhum item válido encontrado, leilões nunca criados.
**Causa**: Código original verificava `item.species` que é nil em muitos itens (species só existe
  em implementos/veículos, não em outros tipos).
**Solução**: Remover verificação de `item.species` e usar `item.isPlaceable` + categorias.

### 3. Assinatura do onUpdate (`main.lua`)
**Sintoma**: `dt` recebia a mission table.
**Causa**: `onUpdate(dt)` — quando usada como `Utils.appendedFunction`, a mission table é passada
  como primeiro argumento, e o `dt` real é o segundo argumento.
**Solução**: `onUpdate(_, dt)`.

### 4. API de Spawn de Veículo (`spawnVehicleForPlayer`)
**Sintoma**: Nenhum erro no log, mas veículo não aparece para o jogador.
**Causa**: Uso de `g_currentMission:loadVehicleFromXML(...)` — esta função **não existe** no
  Farming Simulator 25. Era uma função do FS22 que foi removida.
**Solução**: Substituir por `VehicleLoadingData`, seguindo o padrão comprovado da especialização
  `SupportVehicle` do próprio jogo:

```lua
-- ❌ ERRADO (FS22 API, não existe no FS25)
g_currentMission:loadVehicleFromXML(xmlFilename, farmId, nil, x, y, z, rx, ry, rz, true, false, callback, nil)

-- ✅ CORRETO (FS25 API)
local data = VehicleLoadingData.new()
data:setFilename(xmlFilename)
data:setPosition(x, y, z)
data:setRotation(0, ry, 0)
data:setOwnerFarmId(farmId)
data:setPropertyState(VehiclePropertyState.OWNED)
data:setIsRegistered(false)
data:load(function(callbackTarget, vehicles, loadingState, callbackArgs)
    if loadingState == VehicleLoadingState.OK then
        for _, vehicle in ipairs(vehicles) do
            vehicle:addToPhysics()
            g_currentMission.vehicleSystem:addVehicle(vehicle)
        end
    end
end, nil, nil)
```

### 5. `hasBid` exclui bots (leilão de jogador → bot vence)
**Sintoma**: Quando um jogador leiloa um veículo e um bot vence, o jogador não recebe o dinheiro
  e o veículo não é removido do mundo. Mensagem "Nenhum lance recebido" aparece mesmo com lances.
**Causa**: `AuctionManager.lua:279` — `local hasBid = ... > 0`. Bots têm IDs negativos (-100 a -107),
  então `> 0` retorna `false` para bots. O código cai no `else` (sem lances) e nenhuma transferência
  ocorre.
**Solução**: Substituir `> 0` por `~= 0`:

```lua
-- ANTES (linha 279):
local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId > 0

-- DEPOIS:
local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId ~= 0
```

**Melhoria adicional**: Adicionado desacoplamento de implements antes de `vehicle:delete()` no
  branch `buyerIsBot and not sellerIsBot` para evitar issues com implementos acoplados.

### 6. Transferência de Propriedade sem `isOwnershipTransfer`
**Sintoma**: Em multiplayer, quando um jogador vence o leilão de outro jogador, o veículo
  não muda de dono nos clients.
**Causa**: `vehicle:setOwnerFarmId(farmId)` sem o segundo parâmetro `isOwnershipTransfer = true`.
  A assinatura correta é `setOwnerFarmId(farmId, isOwnershipTransfer)`.
**Solução**:
  1. Adicionar `true` como segundo parâmetro: `vehicle:setOwnerFarmId(winnerId, true)`
  2. Criar `AuctionVehicleTransferEvent.lua` seguindo o padrão `InvoiceVehicleTransferEvent`
     do mod FS25_Invoices (usa `NetworkUtil.getObjectId()`/`getObject()` para serialização,
     e executa `setOwnerFarmId(newOwnerId, true)` no `run()`)
  3. Broadcast do evento após transferência: `g_server:broadcastEvent(AuctionVehicleTransferEvent.new(...))`

### `scripts/AuctionVehicleTransferEvent.lua` — NOVO
Evento de rede para sincronizar transferência de propriedade de veículos entre jogadores.
Segue o mesmo padrão do `InvoiceVehicleTransferEvent` do mod FS25_Invoices:
- Serializa veículo via `NetworkUtil.getObjectId()`/`NetworkUtil.getObject()`
- Executa `vehicle:setOwnerFarmId(newOwnerFarmId, true)` no client ao receber o broadcast

---

## Pesquisa de API — FS25 Vehicle Spawning

### APIs existentes (documentadas no GDN):

| API | Uso | Status |
|-----|-----|--------|
| `VehicleLoadingData` | Classe principal para carregar veículos | ✅ Disponível |
| `BuyVehicleData:buy()` | Usado pela loja para comprar veículos | ✅ Disponível (requer spawn places) |
| `g_currentMission.vehicleSystem:addVehicle()` | Registra veículo no sistema (sincroniza para clients) | ✅ Disponível |
| `vehicle:addToPhysics()` | Adiciona veículo ao mundo físico | ✅ Disponível |
| `vehicle:register()` | Registra veículo na rede | ✅ Disponível (via addVehicle) |
| `g_currentMission:loadVehicleFromXML()` | **Não existe no FS25** | ❌ Removida |
| `VehicleLoadingUtil` | **Não existe no FS25** | ❌ Removida |

### Fluxo de um veículo comprado na loja (referência):

```
BuyVehicleData:buy()
  → VehicleLoadingData.new()
  → data:setStoreItem(storeItem)
  → data:setLoadingPlace(storePlaces, usedStorePlaces)  -- spawn na loja
  → data:setPropertyState(VehiclePropertyState.OWNED)
  → data:setOwnerFarmId(playerFarmId)
  → data:load(onBought, self, args)                      -- async
    → g_currentMission.vehicleSystem:addPendingVehicleLoad(self)
    → veículo é carregado (i3d, specializations, etc.)
    → callback onBought() é chamado
```

### Fluxo do SupportVehicle (usado como referência):

```
SupportVehicle:onLoad()
  → VehicleLoadingData.new()
  → data:setFilename(xmlFilename)
  → data:setPosition(x, y, z)
  → data:setRotation(rx, ry, rz)
  → data:setPropertyState(VehiclePropertyState.OWNED)
  → data:setIsRegistered(false)
  → data:load(onFinishLoadingVehicle, self, nil)
    → callback: vehicle:addToPhysics()
    → callback: g_currentMission.vehicleSystem:addVehicle(vehicle)
```

### Licença e Atribuição

Este mod é baseado no **Server Auction House** original de B.O.B.
As modificações para o sistema de bots foram implementadas como extensão server-authoritative.
