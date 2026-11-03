# Monetization receipts (src/server/Monetization.luau)

- DataStore "PurchaseHistory", key `{PlayerId}_{PurchaseId}`. Values: `{status="pending", at}`, `{status="done", at}`, or legacy `true` (meaning done, from before sprint 4).
- Flow (sprint 4): UpdateAsync only reserves (writes pending). Then the grant runs outside UpdateAsync (handlers may yield). Then a second UpdateAsync marks it done. If the grant fails or returns false, RemoveAsync drops the marker and the decision is NotProcessedYet. If marking done fails, it still returns PurchaseGranted.
- Why: a grant inside the UpdateAsync callback could run twice when the callback is re-run.
- A pending marker younger than PENDING_TIMEOUT (120 s) means busy → NotProcessedYet. An older one is taken over. That's safe only because Coins aren't persisted: a crashed server loses its grant along with it. Revisit this if purchases ever save to a DataStore.
- `Monetization._processReceipt(receipt, store, grant, buyer)` is a test hook; `Monetization.cloud.spec.luau` uses a fake store.
