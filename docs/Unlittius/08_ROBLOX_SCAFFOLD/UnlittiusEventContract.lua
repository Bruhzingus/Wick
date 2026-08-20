-- Reference shared event contract.
-- Claude should merge this with the project's existing remotes/types.

export type BossAction =
    "Idle"
    | "Dripstone"
    | "BoulderBurst"
    | "SummonGnawers"
    | "Melee"
    | "CandleRecoil"
    | "Banish"

export type BossFXPayload = {
    encounterId: string,
    action: BossAction,
    startTime: number,
    seed: number?,
    candleCount: number?,
    targetUserIds: {number}?,
    data: {[string]: any}?,
}

return {}
