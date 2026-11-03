--!strict
-- Everything players can buy with Robux.
-- Game passes are bought once and kept for good; developer products can be bought again and again.
-- Create each one in the Creator Hub (your game → Monetization), then paste its ID below. An ID of 0 means it
-- hasn't been created yet: it can't be bought, and Hangar's ship checklist counts it as missing.
--
-- Examples (the key on the left is what code uses: Monetization.onPass("VIP", ...), Shop.buyPass("VIP")):
--   VIP = { id = 0, name = "VIP", price = 199, description = "A gold name tag and 2x daily reward." },
--   Coins100 = { id = 0, name = "100 Coins", price = 49, description = "100 coins to spend in the shop." },

export type Item = { id: number, name: string, price: number, description: string }

return {
	Passes = {
		NeonTrail = { id = 0, name = "Neon Trail", price = 99, description = "A cyan trail that follows you." },
		VIP = { id = 0, name = "VIP", price = 199, description = "A gold name tag and 2x coins." },
	} :: { [string]: Item },
	Products = {
		Coins100 = { id = 0, name = "100 Coins", price = 49, description = "100 coins to spend in the shop." },
	} :: { [string]: Item },
}
