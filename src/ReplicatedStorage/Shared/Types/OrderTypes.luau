--!strict
--[[
	OrderTypes — shared type definitions for the OrderSystem (Phase 3).
	Types only; no runtime logic. Safe to require from server and client.
]]

export type OrderStatus =
	"Created"
	| "Presented"
	| "Accepted"
	| "Cooking"
	| "Ready"
	| "Served"
	| "Refused"
	| "Cancelled"
	| "Expired"

-- Intent the client may ask for. The server decides the resulting status.
export type OrderAction = "Accept" | "Refuse" | "Serve"

export type CustomerType = "Normal" | "Suspicious" | "Anomaly" | "Mystery" | "Secret"

-- "Presented": customer waiting for the player's decision.
-- "Work": max working time (Accepted -> Served).
export type DeadlineKind = "Presented" | "Work"

export type RecipeDef = {
	displayName: string,
	basePrice: number, -- integer Rupiah. TUNABLE CONFIG
	isGeprek: boolean, -- counts toward MaxGeprekPerOrder
}

export type SambalDef = {
	displayName: string,
	extraPrice: number, -- integer Rupiah added per portion. TUNABLE CONFIG
	weight: number, -- relative spawn weight for generated orders
}

export type ScreenConfig = {
	PartName: string,
	Face: string, -- Enum.NormalId name
	ResultDisplaySeconds: number,
}

export type RemoteNames = {
	FolderName: string,
	ActionFunction: string,
	SnapshotFunction: string,
	UpdateEvent: string,
}

export type DebugConfig = {
	EnableDevHarness: boolean, -- only honoured inside Roblox Studio
	DevAutoCook: boolean, -- Phase 4 CookingService now owns Cooking/Ready; keep false normally
	DevAutoCookSeconds: number,
	DevNextOrderDelaySeconds: number,
	RunSelfTest: boolean, -- only honoured inside Roblox Studio
}

export type OrderConfig = {
	MaxGeprekPerOrder: number,
	MaxLinesPerOrder: number,
	WorkTimeLimitSeconds: number,
	PresentedTimeoutSeconds: number,
	MaxInteractDistance: number,
	ActionCooldownSeconds: number,
	MaxIdLength: number,
	MaxFinishedHistory: number,
	DefaultRecipeId: string,
	Recipes: { [string]: RecipeDef },
	Sambal: { [string]: SambalDef },
	SambalOrder: { string },
	PortionWeights: { [number]: number },
	Screen: ScreenConfig,
	Remotes: RemoteNames,
	Debug: DebugConfig,
}

export type OrderLine = {
	recipeId: string,
	sambalId: string,
	quantity: number,
}

-- Server-side record. NEVER replicate this directly; send OrderSummary instead.
export type Order = {
	orderId: string,
	seq: number,
	customerId: string,
	customerCategory: CustomerType,
	lines: { OrderLine },
	totalQuantity: number,
	totalPrice: number,
	status: OrderStatus,
	createdAt: number,
	presentedAt: number?,
	acceptedAt: number?,
	finishedAt: number?,
	deadlineAt: number?,
	deadlineKind: DeadlineKind?,
	endReason: string?,
	ownerUserId: number?,
	metadata: { [string]: any },
}

export type OrderLineSummary = {
	recipeId: string,
	displayName: string,
	sambalId: string,
	sambalName: string,
	quantity: number,
	unitPrice: number,
	lineTotal: number,
}

-- Client-safe view. Contains no customer category, anomaly flags or metadata.
export type OrderSummary = {
	orderId: string,
	customerId: string,
	status: OrderStatus,
	lines: { OrderLineSummary },
	totalQuantity: number,
	totalPrice: number,
	deadlineAt: number?, -- workspace:GetServerTimeNow() based
	deadlineKind: DeadlineKind?,
	endReason: string?,
}

export type CreateOrderParams = {
	customerId: string,
	customerCategory: CustomerType?,
	lines: { OrderLine }?, -- omitted => server generates from config
	ownerUserId: number?,
	metadata: { [string]: any }?,
	present: boolean?, -- default true: Created -> Presented immediately
	rng: Random?,
}

export type ActionResult = {
	ok: boolean,
	code: string,
}

return {}
