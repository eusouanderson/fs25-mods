# FS25 Server Auction House - Correções (21 Jun 2026)

## Problemas Identificados e Corrigidos

### 1. Bot-bot auction crash ("veículo não encontrado")
- **Arquivo**: `AuctionManager.lua` — `resolveAuction()`
- **Problema**: Leilões onde ambos os lados são bots caíam no `else` (player-to-player), que tenta `getVehicleById(0)` — bot auctions têm `vehicleId=0`.
- **Correção**: Novo `elseif buyerIsBot and sellerIsBot` — loga como transferência virtual e broadcast, sem transferir veículo.

### 2. Silent spawn failure (vehicle never delivered, money lost)
- **Arquivo**: `AuctionBotManager.lua` — `spawnVehicleForPlayer()`
- **Problema**: Se `getItemByXMLFilename` falha, `VehicleLoadingData` fica vazio (`isValid = false`). `load()` nunca dispara callback quando `#vehicles == 0`. Jogador perde dinheiro sem receber veículo.
- **Correção**: Guard `if not data.isValid` antes de `load()`, retorna `false`.

### 3. No refund on spawn failure
- **Arquivo**: `AuctionManager.lua` — `resolveAuction()` (branch player-wins-bot)
- **Problema**: Dinheiro debitado ANTES de spawnar, sem verificar resultado de `spawnVehicleForPlayer`.
- **Correção**: Verifica `spawnOk`, reembolsa (`changeBalance(+currentBid)`) se `false`.

### 4. No refund when xmlFilename is nil
- **Arquivo**: `AuctionManager.lua` — `resolveAuction()` (branch player-wins-bot)
- **Correção**: Adicionado reembolso quando `xmlFilename` é `nil`.

### 5. Orphaned ENDED auctions from previous (buggy) version
- **Arquivo**: `AuctionManager.lua` — `loadFromSavegame()`
- **Problema**: Savegame acumula leilões com `status=ENDED` do código antigo (pre-v1.2.0). O código antigo verificava `highestBidderId > 0`, achava `vehicleId=0`, mostrava "vehicle not found" mas nunca debitava nem spawnava.
- **Correção**: No `loadFromSavegame()`, re-ativa como `ACTIVE` (com `endTime=0`) leilões ENDED onde `sellerId < 0` (bot), `highestBidderId > 0` (player), `currentBid > 0`, e `xmlFilename` contém `/vehicles/`. O próximo `update()` processa com a lógica atual. Savegame é limpo automaticamente.

### 6. Placeable filter reinforcement
- **Arquivo**: `AuctionBotManager.lua` — `getRandomStoreItem()`
- **Problema**: `item.isPlaceable` pode ser `nil` para alguns placeables, deixando passar.
- **Correção**: Adicionado `item.xmlFilename:find("/placeables/") == nil` como backup.

## Fluxo de Resolução (resolveAuction)

```
if hasBid (highestBidderId ~= 0)
  ├── buyerIsBot AND NOT sellerIsBot  → Bot wins player auction: deleta veículo do mundo, credita jogador
  ├── NOT buyerIsBot AND sellerIsBot  → Player wins bot auction: debita jogador, spawnVehicleForPlayer (com refund se falhar)
  ├── buyerIsBot AND sellerIsBot      → Bot-bot: virtual trade, sem ação
  └── else                            → Player-to-player: setOwnerFarmId, transfere dinheiro
else
  → Sem lances: broadcast
```

## spawnVehicleForPlayer Flow
1. Obtém posição de spawn (shopSpawnPlaces ou perto do jogador)
2. `g_storeManager:getItemByXMLFilename(xmlFilename)` — pré-valida store item
3. `VehicleLoadingData.new()` + `setStoreItem()` ou `setFilename()` fallback
4. Guard: `if not data.isValid then return false end`
5. Configura posição, rotação, owner, property state
6. `data:load()` — async callback:
   - OK + vehicles > 0: `addToPhysics()`, `vehicleSystem:addVehicle()`
   - OK + vehicles == 0: log erro (silent failure)
   - Error: log erro

## Observações
- Bot IDs são negativos (-100 a -107), player IDs positivos (1+)
- `hasBid` usa `~= 0` (não `> 0`) para incluir bots
- Leilões de bot sempre têm `vehicleId = 0` (não existe veículo no mundo)
- DLC items com caminho absoluto Windows (`F:/Games/...`) podem falhar `getItemByXMLFilename`
