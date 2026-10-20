--!strict
--[[
	CurrencyFormat — display-only Rupiah formatting (e.g. 1250000 -> "Rp1.250.000").
	Money is stored as integer Rupiah everywhere else; format only inside UI.
]]

local CurrencyFormat = {}

function CurrencyFormat.formatRupiah(amount: number): string
	local rounded = math.floor(math.abs(amount) + 0.5)
	local reversed = string.reverse(tostring(rounded))
	local withDots = string.gsub(reversed, "(%d%d%d)", "%1.")
	local restored = string.reverse(withDots)
	restored = string.gsub(restored, "^%.", "")
	local sign = if amount < 0 then "-" else ""
	return sign .. "Rp" .. restored
end

return CurrencyFormat
