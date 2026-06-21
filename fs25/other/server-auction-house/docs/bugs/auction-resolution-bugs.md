# Bugs na Resolução de Leilões

## Bug 1: Jogador ganha leilão de bot → veículo não entregue

### Sintoma
7 leilões contra bots (IDs 7, 8, 9, 11, 12, 13, 16) constam como `status="ENDED"`,
`highestBidderId="1"` (jogador). Total de ~384k pago. Veículos nunca apareceram.

### Savegame (server_auctions.xml)
```
ID 7:  G340                     - data/s_Steering/S_Steering.xml
ID 8:  Rapide Trailered         - data/vehicles/trailers/koluman/...
ID 9:  Rapide Trailered         - data/vehicles/trailers/koluman/...
ID 11: hTS 22B.79               - data/vehicles/tractors/steyr/hts/...
ID 12: L630                     - data/vehicles/tractors/kirovetz/...
ID 13: RBM2000                  - data/vehicles/cutters/grimm/...
ID 16: lodgepolePine_stage03    - data/foliage/trees/lodgepolePine/...
```

### Causa Raiz: `getRandomStoreItem()` inclui não-veículos

`AuctionBotManager.getRandomStoreItem()` usa `g_storeManager:getItems()`, que
retorna **todos** os itens da loja — incluindo árvores, placeables, etc.

`VehicleLoadingData:setFilename(xmlFilename)` chama internamente
`g_storeManager:getItemByXMLFilename()`. Se o XML não for de um veículo
(ex: árvore ID 16), o lookup falha silenciosamente — `self.vehicles` fica vazio.

### Causa Raiz: `VehicleLoadingData:load()` com lista vazia → callback nunca chamado

```lua
function VehicleLoadingData:load(callback, ...)
    self.vehiclesToLoad = #self.vehicles  -- = 0
    -- for de validação: não executa (vazio)
    -- for de loadVehicle: não executa (vazio)
    -- callback NUNCA é chamado
    -- loadingState = OK
end
```

O callback que deveria chamar `addToPhysics()` + `vehicleSystem:addVehicle()`
nunca dispara. Nenhum erro no log.

### Causa Raiz: Dinheiro debitado ANTES do spawn

Em `resolveAuction()`:
```lua
-- 1. Débito (sempre executado)
playerFarm:changeBalance(-auction.currentBid, ...)
-- 2. Tentativa de spawn (se falhar, dinheiro já foi)
AuctionBotManager.spawnVehicleForPlayer(...)
```

Sem mecanismo de reembolso.

### Causa Raiz: Leilões ENDED persistem no savegame

`onSaveToXMLFile()` salva `self.auctions` inteiro. Entre `resolveAuction()` e o
próximo `update()` que os remove, um salvamento pode acontecer. Os ENDED
persistem para sempre.

---

## Bug 2: Jogador leiloa → Bot ganha → dinheiro não creditado, veículo não some

### Sintoma
Quando o jogador coloca um item à venda e um bot vence o leilão:
- O dinheiro do lance NÃO é creditado ao jogador
- O veículo NÃO é removido do mundo
- A mensagem "Nenhum lance recebido" é exibida

### Causa Raiz: `hasBid` usa `> 0` que exclui bots

**Arquivo:** `AuctionManager.lua`, linha 279

```lua
local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId > 0
```

Bots têm IDs **negativos** (-100 a -107). A condição `> 0` retorna `false`
para bots, fazendo `hasBid = false`. O código cai no `else`:

```lua
else
    self:broadcastChat(string.format(g_i18n:getText("ah_global_noBids", ...), auction.itemName))
end
```

Nenhuma transferência de dinheiro ou remoção de veículo ocorre.

### Fluxo do bug

```
createAuction(sellerId=1, vehicleId=123)
  → Bot bid (-100) → highestBidderId = -100
    → resolveAuction()
      → hasBid = (-100 > 0) = false ✗
        → else: "Nenhum lance recebido"
          → seller NÃO recebe dinheiro
          → veículo NÃO é deletado
```

### Fluxos não afetados

**Bot leiloa → Jogador ganha:**
```
highestBidderId = 1 (positivo) → hasBid = true ✓
→ not buyerIsBot and sellerIsBot: spawn veículo
```

**Online Jogador→Jogador:**
```
highestBidderId = 2 (positivo) → hasBid = true ✓
→ else: setOwnerFarmId, transferir dinheiro
```

### Correção

Uma linha:

```lua
-- ANTES:
local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId > 0

-- DEPOIS:
local hasBid = auction.highestBidderId ~= nil and auction.highestBidderId ~= 0
```

### Melhoria: Desacoplar implements antes de deletar

No branch `buyerIsBot and not sellerIsBot` (bot ganha item do player),
`vehicle:delete()` é chamado sem desacoplar implements primeiro. Adicionar:

```lua
if vehicle.getAttachedImplements ~= nil then
    local implements = vehicle:getAttachedImplements()
    local numImplements = implements ~= nil and #implements or 0
    if numImplements > 0 then
        for i = numImplements, 1, -1 do
            vehicle:detachImplement(1)
        end
    end
end
```

---

## Resumo das Correções

| # | O quê | Arquivo | Linha |
|---|-------|---------|-------|
| 1 | `hasBid`: `> 0` → `~= 0` | `AuctionManager.lua` | 279 |
| 2 | Desacoplar implements antes de deletar | `AuctionManager.lua` | ~285 |
| 3 | Filtrar não-veículos em `getRandomStoreItem` | `AuctionBotManager.lua` | 136-146 |
| 4 | Limpar ENDED do savegame na carga | `AuctionStorage.lua` | 19-63 |
| 5 | Reembolso se spawn falhar | `AuctionManager.lua` | ~300-315 |

Items 3-5 são melhorias futuras não implementadas nesta versão.
