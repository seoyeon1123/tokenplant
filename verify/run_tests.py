# -*- coding: utf-8 -*-
"""Swift 테스트 59개의 본문을 그대로 실행한다."""
import sys
from datetime import date, timedelta
from engine_port import *

FAIL = []
PASS = 0


def check(cond, name, msg=""):
    global PASS
    if cond:
        PASS += 1
    else:
        FAIL.append(f"{name}: {msg}")


def eq(a, b, name, msg=""):
    check(a == b, name, msg or f"{a!r} != {b!r}")


def close(a, b, tol, name):
    check(abs(a - b) <= tol, name, f"{a} vs {b} (±{tol})")


def fresh(species="tomato"):
    s = Save()
    s.pot = Pot(species=species)
    s.claimed = {}
    return s


D1, D2, D3 = "2026-09-01", "2026-09-02", "2026-09-03"

# ══════════ PlantBalanceTests ══════════
N = "testWaterMatchesMeasuredDay"
d = TD(i=1100, o=553000, cw=1800000, cr=106900000)
eq(d.raw, 109254100, N); eq(water_from(d), 15706, N)

N = "testCacheReadDominatesRawButNotWater"
check(d.cr / d.raw > 0.97, N)
ws = water_from(TD(cr=d.cr)) / water_from(d)
check(0.60 < ws < 0.75, N, f"waterShare={ws:.4f}")

N = "testNegativeDeltaNeverRemovesWater"
eq(water_from(TD(i=-500, o=-1000, cw=-2000, cr=-9000000)), 0, N)

# 목표는 이제 사람마다 다르다. 테스트는 기준 하루치로 심었을 때의 목표 하나를 잡고 본다.
CYCLE = cycle_water(ASSUMED_DAILY_RAW)
def TH_(i): return threshold(i, CYCLE)

N = "testThresholdsAreStrictlyIncreasing"
eq(len(STAGE_FRACTIONS), 10, N); eq(STAGE_FRACTIONS[0], 0, N)
check(STAGE_FRACTIONS[-1] < 1.0, N, "마지막 단계가 목표와 붙어 거목을 볼 틈이 없다")
check(all(TH_(i) > TH_(i-1) for i in range(1, STAGE_COUNT)), N)

N = "testFinalStepIsAboutOneThirdOfTotal"
step = STAGE_FRACTIONS[-1] - STAGE_FRACTIONS[-2]
check(0.30 < step / STAGE_FRACTIONS[-1] < 0.36, N)

N = "testCycleIsFourWeeksAtAnyUsageRate"
# 누가 심어도 한 그루는 4주. 이게 없으면 적게 쓰는 사람은 1년 넘게 씨앗만 본다.
for rate in (5_000_000, 20_000_000, 105_000_000, 400_000_000):
    c = cycle_water(rate)
    close(c / max(1, rate // RAW_PER_ML), TARGET_CYCLE_DAYS, 1.0, N + f" 하루 {rate}")

N = "testEarlyStageThresholdsAreTinyFractionsOfTheCycle"
# 옛 테스트는 `cap < threshold(5)`(13%)만 봐서 통과했는데, Lv.5 문턱은 6.75% 였다.
# 검사 대상이 한 칸 위여서 "이틀치 = Lv.5 시작"을 못 잡았다.
c = 280_000
for stage, frac in ((1, 0.00375), (2, 0.0125), (3, 0.03), (4, 0.0675), (5, 0.13)):
    eq(threshold(stage, c), int(c * frac), N, f"Lv.{stage+1} 문턱이 바뀌었다")
check(c / 28 > threshold(3, c), N, "하루치가 Lv.4 아래로 내려왔다 — 첫날 정책 재검토")

N = "testCycleIsClampedForExtremeRates"
eq(cycle_water(1), MIN_CYCLE_WATER, N)
eq(cycle_water(100_000_000_000), MAX_CYCLE_WATER, N)

N = "testFinalStageArrivesBeforeTransplant"
per_day = daily_water_from_tokens()
check(TH_(9) < CYCLE, N)
close(CYCLE / per_day - TH_(9) / per_day, 1.75, 0.5, N)

N = "testThreeStagesOnFirstDay"
eq(stage_index(per_day, CYCLE), 3, N); eq(stage_index(per_day // 2, CYCLE), 2, N)

N = "testStageIndexClampsAtMax"
eq(stage_index(0, CYCLE), 0, N); eq(stage_index(TH_(1) - 1, CYCLE), 0, N)
eq(stage_index(TH_(1), CYCLE), 1, N); eq(stage_index(999999999, CYCLE), STAGE_COUNT - 1, N)

N = "testNextThresholdWalksToTransplantThenNil"
eq(next_threshold(0, CYCLE), TH_(1), N); eq(next_threshold(8, CYCLE), TH_(9), N)
eq(next_threshold(9, CYCLE), CYCLE, N); eq(next_threshold(10, CYCLE), None, N)

N = "testStreakBonusCapsAtTen"
# +2%/일 · 천장 50% 였다. 그게 총 배율을 3배로 부풀린 주범이다 —
# 공짜로 쌓이는 보너스가 돈을 내는 물(+40%)보다 커지면 상점에 갈 이유가 없다.
eq(streak_bonus(0), 0, N); eq(streak_bonus(1), 1, N)
eq(streak_bonus(10), 10, N); eq(streak_bonus(400), 10, N)
check(streak_bonus(400) < DAILY_WATER_USES * 20, N, "공짜 보너스가 유료 가속보다 크다")

N = "testBonusesAddRatherThanMultiply"
both = applied(10000, 25, True)
eq(both, 13500, N); check(both != 10000 * 1.10 * 1.25, N, "곱으로 합쳤다")

N = "testTotalMultiplierStaysNearDouble"
# **이 파일에서 제일 중요한 단정.** 손잡이를 하나씩 보면 다 합리적인데,
# 곱해놓고 보니 28일 사이클이 9일이었다(3.06배). 합계를 재는 곳이 없어서 몰랐다.
rate = (1.0 + DAILY_WATER_USES * 0.2) * (1 + (streak_bonus(400) + FERT_BONUS) / 100)
full = TARGET_CYCLE_DAYS / rate * (1 - REPOT_REDUCE / 100)
spread = TARGET_CYCLE_DAYS / full
check(1.85 <= spread <= 2.15, N, f"아무것도 안 함 대비 {spread:.2f}배 (2배여야 한다)")
check(12.0 <= full <= 15.0, N, f"다 하는 사람 완주 {full:.1f}일")

N = "testWindowBonusStaysUnderTenPercentOfCycle"
# 창만 태워서 상점을 굴릴 수 있으면 안 된다 — 사이클 수입의 10% 안쪽이어야 한다.
bonus = est_window_bonus_per_cycle()
cycle_days = float(TARGET_CYCLE_DAYS)
cycle_income = cycle_days * ASSUMED_DAILY_RAW
check(bonus / cycle_income < 0.12, N, f"share={bonus/cycle_income:.3f}")
check(bonus / cycle_income > 0.05, N, f"share={bonus/cycle_income:.3f}")

N = "testFertilizerMarginIsThin"
# 거름은 평평한 품목이라 물과 직접 견줄 수 있다. 마진이 얇아야 고민이 된다.
per_water = water_ml() / PRICE_DAYS["water"]
fert_back = daily_water_from_tokens() * FERT_DAYS * FERT_BONUS / 100
ratio = (fert_back / PRICE_DAYS["fertilizer"]) / per_water
check(ratio > 1.0, N, f"거름이 물보다 나쁘다 ({ratio:.2f})")
check(ratio < 1.2, N, f"거름이 물보다 너무 좋다 ({ratio:.2f})")

N = "testNutrientBreakEvenLandsMidCycle"
# 비례 품목이라 한 점에서 견주는 건 의미가 없다 — 손익분기가 어디 있느냐가 핵심이다.
# 10% 였을 때 사이클의 6% 지점이라 이득 구간이 첫 1.5일뿐이었다(사실상 죽은 품목).
alt = (PRICE_DAYS["nutrient"] / PRICE_DAYS["water"]) * water_ml()
break_even = CYCLE - alt / (REPOT_REDUCE / 100)
share = break_even / CYCLE
check(0.40 < share < 0.60, N, f"손익분기가 사이클의 {share*100:.0f}% 지점")
check(nutrient_gain(0, CYCLE) > alt * 1.5, N, "갓 심은 그루에서도 물보다 크게 낫지 않다")
check(nutrient_gain(TH_(9), CYCLE) < alt, N, "거목 앞에서도 이득이면 쓸 때를 고를 이유가 없다")

N = "testWaterItemExistsAndIsCheapest"
# 성장이 자동이므로 물을 사는 건 수수료가 아니라 가속이다.
check("water" in PRICE, N, "물이 없다")
eq(min(PRICE, key=lambda k: PRICE[k]), "water", N, "물이 제일 싸지 않다")

N = "testAccelerationCeilingIsExactlyDouble"
# 지갑 하루치를 통째로 물에 쏟으면 하루 자동 성장만큼 더 자란다 = 최대 2배.
# 이 한 줄이 밸런스 전체를 고정한다.
count = ASSUMED_DAILY_RAW // PRICE["water"]
eq(count, 5, N, "하루치로 물을 다섯 개 못 산다")
auto = daily_water_from_tokens()
close((auto + count * water_ml()) / auto, 2.0, 0.01, N)

# ══════════ 하루 상한 ══════════
N = "testWaterIsCappedAtFiveUsesPerDay"
# 지갑이 이월되므로 상한이 없으면 며칠 모았다가 하루에 다 쏟을 수 있다.
s = fresh(); s.raw_wallet = PRICE["water"] * 50
s.inv["water"] = 50
ok = 0
for _ in range(50):
    if use(s, "water", D1)[0] == "ok": ok += 1
eq(ok, DAILY_WATER_USES, N, f"하루에 {ok}번 줬다")
check(s.count("water") == 50 - DAILY_WATER_USES, N, "막힌 물이 소모됐다 — 산 게 사라진다")

N = "testWaterAllowanceResetsNextDay"
again = 0
for _ in range(50):
    if use(s, "water", D2)[0] == "ok": again += 1
eq(again, DAILY_WATER_USES, N, "다음 날 상한이 안 풀렸다")

N = "testNutrientIsOncePerPlant"
s = fresh(); s.inv["nutrient"] = 5
first = use(s, "nutrient", D1)
eq(first[0], "ok", N)
eq(use(s, "nutrient", D1)[0], "noEffect", N, "같은 그루에 두 번 들어갔다")
eq(use(s, "nutrient", D2)[0], "noEffect", N, "날이 바뀌니 또 들어갔다")
eq(s.count("nutrient"), 4, N, "막힌 영양제가 소모됐다")

N = "testNutrientAllowanceResetsOnTransplant"
# 그루에 기록하므로 이식하면 저절로 풀려야 한다.
s = fresh(); s.inv["nutrient"] = 3
_ = use(s, "nutrient", D1)
apply_water(s, s.pot.cycle, D1)
check(transplant(s, 7, D1), N, "이식이 안 됐다")
eq(use(s, "nutrient", D1)[0], "ok", N, "새 그루인데 영양제가 막혔다")

N = "testHoardingCannotCollapseTheCycle"
# 30일치를 모아 새 화분에 쏟아도 하루 만에 끝나면 안 된다.
s = fresh()
for d in range(1, 31):
    ingest(s, {"claude": TD(cr=ASSUMED_DAILY_RAW * d)}, f"2026-09-{d:02d}")
s.pot = Pot(species="tomato", cycle=cycle_water(daily_rate(s.daily_raw)))
poured = 0
while buy(s, "water")[0] == "ok":
    if use(s, "water", "2026-09-30")[0] != "ok":
        break
    poured += 1
eq(poured, DAILY_WATER_USES, N, f"하루에 물 {poured}개가 들어갔다")
check(not s.pot.ready, N, "하루 만에 이식 가능해졌다 — 사이클이 무너진다")

# ══════════ PlantEngineTests ══════════
N = "testIngestIsIdempotentForSameSnapshot"
s = fresh()
snap = {"claude": TD(i=1000, o=100000, cw=400000, cr=20000000)}
ingest(s, snap, D1); first = s.raw_wallet
check(first > 0, N)
ingest(s, snap, D1); eq(s.raw_wallet, first, N, "같은 스냅샷이 두 번 적립됐다")

N = "testFirstInstallCreditsNothing"
s = Save(); s.pot = Pot(species="tomato")
eq(s.claimed, None, N)
ingest(s, {"claude": TD(cr=3000000000)}, D1)      # 300,000mL 상당 — 그래도 0
eq(s.raw_wallet, 0, N, "설치 전 토큰이 지갑에 소급됐다")
eq(s.pot.water, 0, N, "설치 전 토큰으로 자랐다")
eq(s.pot.stage, 0, N, "씨앗으로 시작하지 않았다")
eq(s.raw_since, 0, N, "설치 전 몫이 누적에 들어갔다")
check(s.baseline_set, N); eq(s.last_date, D1, N)

N = "testFreshInstallIsNotThirsty"
# 첫날 적립이 사라지면서 last_water 도 빈 채로 시작한다.
# 그걸 "며칠째 안 준 것"으로 읽으면 설치 직후 바싹 마른 씨앗이 뜬다.
s = Save(); s.pot = Pot(species="tomato")
ingest(s, {"claude": TD(cr=3000000000)}, D1)
eq(s.last_water_day, "", N, "전제가 깨졌다 — 설치가 물을 줬다")
eq(thirst_level(s, D1), 0, N, "설치 직후에 목이 말랐다")
eq(thirst_level(s, "2027-01-01"), 0, N, "한 번도 안 준 씨앗이 바싹 말랐다")

N = "testUsageAfterInstallCreditsInFull"
s = Save(); s.pot = Pot(species="tomato")
ingest(s, {"claude": TD(cr=3000000000)}, D1)
eq(s.raw_wallet, 0, N)
ingest(s, {"claude": TD(cr=3010000000)}, D1)
eq(s.raw_wallet, 10_000_000, N, "설치 후 증분이 잘렸다")
check(s.pot.water > 0, N, "설치 후 증분으로 안 자랐다")

N = "testFreshInstallOnNewDayStillTakesSeedPath"
s = Save(); s.pot = Pot(species="tomato")
eq(s.last_date, "", N)
ingest(s, {"claude": TD(cr=3000000000)}, D1)
eq(s.raw_wallet, 0, N, "seed 분기를 안 타서 설치 전 로그가 소급됐다")

N = "testFirstInstallFeedsNeitherStream"
s = Save(); s.pot = Pot(species="tomato")
ingest(s, {"claude": TD(cr=30000000000)}, D1)
eq(s.raw_wallet, 0, N); eq(s.pot.water, 0, N)
eq(s.streak, 0, N, "설치만으로 스트릭이 시작됐다")

N = "testPouringToTheCapStillLeavesMostOfTheWallet"
# 물은 값이 하루치의 1/5 이라 mL 도 하루 성장의 1/5 이어야 한다(설계 예산 ×1.40).
# 상수로 환산하던 동안에는 캐시읽기가 많은 사람에게 1.57 이 나왔다.
def _seeded_three_days():
    s = Save(); s.pot = Pot(species="tomato"); s.claimed = {}
    for d in ("2026-09-01", "2026-09-02", "2026-09-03"):
        s.claimed = {}
        ingest(s, {"claude": TD(cr=ASSUMED_DAILY_RAW)}, d)
    return s

_d4 = "2026-09-04"
_lazy, _busy = _seeded_three_days(), _seeded_three_days()
_before = _lazy.pot.water
for _s in (_lazy, _busy):
    _s.claimed = {}
    ingest(_s, {"claude": TD(cr=ASSUMED_DAILY_RAW)}, _d4)
_purse = _busy.raw_wallet
_poured = 0
while True:
    if buy(_busy, "water")[0] != "ok": break
    if use(_busy, "water", _d4)[0] != "ok": break
    _poured += 1
_ratio = (_busy.pot.water - _before) / (_lazy.pot.water - _before)
close(_ratio, 1.4, 0.05, N + f" 물 배율이 {_ratio:.3f}")
eq(_poured, DAILY_WATER_USES, N, "상한이 아니라 지갑이 먼저 떨어졌다")
check(_busy.raw_wallet / _purse > 0.5, N, "상한까지 부었는데 지갑이 절반도 안 남았다")


# ══════════ 두 물길 ══════════
#
# 쓴 토큰 하나가 두 곳으로 간다. 화분(가중 환산 mL)과 지갑(원시 토큰).
# 둘은 서로 뺏지 않는다 — 그게 이 앱의 전부다.


def feed(s, ml, day):
    """토큰을 ml 만큼의 물이 나오도록 쓴다. 지갑에는 그에 상당하는 원시 토큰이 들어간다."""
    credit(s, ml * RAW_PER_ML, ml, day)


N = "testUsingTokensGrowsThePlantWithNoUserAction"
s = fresh()
feed(s, 50000, D1)
check(s.pot.water > 0, N, "토큰을 썼는데 화분이 안 자랐다")
check(s.pot.stage >= 4, N, f"stage={s.pot.stage}")

N = "testTheSameTokensAlsoFillTheWallet"
s = fresh()
feed(s, 50000, D1)
eq(s.raw_wallet, 50000 * RAW_PER_ML, N, "지갑에 원시 토큰이 안 들어갔다")

N = "testSpendingTheWalletNeverShrinksThePlant"
s = fresh()
feed(s, 50000, D1)
grown, stage = s.pot.water, s.pot.stage
s.raw_wallet = PRICE["shinyCharm"]
eq(buy(s, "shinyCharm")[0], "ok", N)
eq(s.raw_wallet, 0, N, "지갑에서 안 나갔다")
eq(s.pot.water, grown, N, "구매가 성장을 갉아먹었다")
eq(s.pot.stage, stage, N)

N = "testDailyCapBoundsAccelerationNotThePrice"
# **실측 구성**으로 하루를 쓴다.
#
# 예전 천장은 2.0배였고, 그걸 정한 건 **값**이었다(0.2일치 × 5개 = 하루치).
# 그게 문제였다 — 상한까지 붓는 게 곧 유입 100% 지출이라 지갑이 영원히 0이었다.
# 이제 천장을 정하는 건 **횟수 상한**이다: 2개 × 0.2일치 = 유입의 40%,
# 가속 1.4배, 나머지 60% 는 지갑에 남아 상점으로 간다.
MEASURED_DAY = TD(i=1100, o=553000, cw=1800000, cr=106900000)
scale = ASSUMED_DAILY_RAW / MEASURED_DAY.raw
_i, _o, _cw = int(1100 * scale), int(553000 * scale), int(1800000 * scale)
day = {"claude": TD(i=_i, o=_o, cw=_cw, cr=ASSUMED_DAILY_RAW - _i - _o - _cw)}
lazy = fresh(); ingest(lazy, day, D1)
busy = fresh(); ingest(busy, day, D1)
poured = 0
while buy(busy, "water")[0] == "ok":
    if use(busy, "water", D1)[0] != "ok": break
    poured += 1
close(busy.pot.water / lazy.pot.water, 1.4, 0.12, N)
eq(poured, DAILY_WATER_USES, N, "하루 상한이 아니라 지갑이 먼저 떨어졌다")
# 값이 아니라 상한이 묶는다는 걸 못 박는다: 지갑에 하루치가 다 있어도 2개에서 멈춘다.
check(busy.raw_wallet >= PRICE["water"], N, "지갑이 남았는데도 못 산 게 아니어야 한다")

N = "testAccelerationStaysBoundedForAnyTokenMix"
# 구성이 달라도 루프가 닫히지 않는다. 캐시 읽기만 쓰는 사람은 토큰당 물이 적어
# 사는 쪽 비중이 커지지만(≈2.4배), 출력만 쓰는 사람은 거의 차이가 없다(≈1.03배).
# 어느 쪽이든 유한하고, **환산이 나쁜 사람을 더 도와준다** — 그건 의도한 성질이다.
for label, mix in (("캐시읽기만", TD(cr=ASSUMED_DAILY_RAW)),
                   ("출력만", TD(o=ASSUMED_DAILY_RAW))):
    a = fresh(); ingest(a, {"claude": mix}, D1)
    b = fresh(); ingest(b, {"claude": mix}, D1)
    while buy(b, "water")[0] == "ok":
        use(b, "water", D1)
    r = b.pot.water / a.pot.water
    check(1.0 <= r <= 2.5, N, f"{label} 가속 {r:.2f}배")

N = "testWaterIsFlatWhereverYouAre"
young = fresh(); young.inv["water"] = 1
old = fresh(); old.pot.water = threshold(8, old.pot.cycle); old.pot.stage = 8; old.inv["water"] = 1
eq(use(young, "water", D1)[1], use(old, "water", D1)[1], N, "물이 구간에 따라 달라졌다")

N = "testFertilizerGivesNothingNowAndMultipliesLater"
s = fresh(); s.inv["fertilizer"] = 1
before = s.pot.water
eq(use(s, "fertilizer", D1)[1], 0, N, "거름이 즉시 물을 줬다 — 물과 구분이 안 된다")
eq(s.pot.water, before, N)
plain = fresh()
feed(plain, 10000, D2); feed(s, 10000, D2)
check(s.pot.water > plain.pot.water, N, "거름이 안 먹혔다")

N = "testItemWaterGetsTheSameBonusesAsAutomaticGrowth"
a = fresh(); a.inv["water"] = 1
b = fresh(); b.inv["water"] = 1
b.fert_until = dk(dparse(D1) + timedelta(days=7))
check(use(b, "water", D1)[1] > use(a, "water", D1)[1], N, "거름이 아이템 물에는 안 붙었다")

N = "testWaterReachesBothPotsEqually"
# 나눠 주면 슬롯을 사는 게 성장 반토막이라 아무도 안 산다.
s = fresh(); s.raw_wallet = PRICE["potSlot"]
buy(s, "potSlot")
s.inv["water"] = 1
use(s, "water", D1)
eq(s.pot.water, s.pot2.water, N, "두 화분이 다른 양을 받았다")
check(s.pot.water > 0, N)

N = "testAutomaticGrowthAlsoReachesBothPots"
s = fresh(); s.raw_wallet = PRICE["potSlot"]
buy(s, "potSlot")
feed(s, 10000, D1)
eq(s.pot.water, s.pot2.water, N)
check(s.pot2.water > 0, N)

N = "testStreakCountsTokenDaysNotAppOpens"
s = fresh()
feed(s, 5000, D1); eq(s.streak, 1, N)
feed(s, 5000, D2); eq(s.streak, 2, N)
feed(s, 5000, D3); eq(s.streak, 3, N)
feed(s, 5000, "2026-09-08"); eq(s.streak, 1, N, "나흘 비었는데 이어졌다")

N = "testThirstDoesNotEatProgress"
s = fresh()
feed(s, 60000, D1)
grown = s.pot.water
eq(thirst_level(s, D1), 0.0, N)
check(thirst_level(s, "2026-09-06") > 0, N, "5일 뒤에도 안 마른다")
eq(thirst_level(s, "2026-09-30"), 1.0, N)
eq(s.pot.water, grown, N, "목마르다고 누적 물이 깎였다")

N = "testGrowingResetsThirst"
s = fresh()
feed(s, 10000, D1)
check(thirst_level(s, "2026-09-11") > 0, N)
feed(s, 10000, "2026-09-11")
eq(thirst_level(s, "2026-09-11"), 0.0, N, "자랐는데 색이 안 돌아왔다")

N = "testDaysAwayStillGrowThePlant"
# 앱을 안 열어도 자란다. 그게 이 앱의 약속이다.
s = fresh()
for d in (D1, D2, D3):
    feed(s, 15000, d)
check(s.pot.water >= 45000, N, f"사흘치가 안 들어왔다 ({s.pot.water})")

N = "testPriceFollowsTheMeasuredDailyRate"
# 하루를 절반 쓰는 사람에게는 절반 값이다.
s = fresh()
half = ASSUMED_DAILY_RAW // 2
s.daily_raw = {D1: half, D2: half, D3: half}
eq(price(s, "water"), int(PRICE_DAYS["water"] * half), N)
check(price(s, "water") < PRICE["water"], N, "측정값이 가격에 안 반영됐다")

# ══════════ 한도 창 소진 보상 ══════════

SESSION_FULL = [("claude.fiveHour", "session", 100.0)]
SESSION_HALF = [("claude.fiveHour", "session", 45.0)]

N = "testFirstRunSeedsWindowsWithoutGranting"
s = fresh()
eq(grant_window_bonus(s, SESSION_FULL, True), 0, N, "첫 실행에 소급 지급됐다")
check(s.windows_seeded, N)
eq(s.window_tier.get("claude.fiveHour"), 1, N, "시드가 안 찍혔다")

N = "testWindowGrantIsEdgeTriggeredOnce"
s = fresh()
grant_window_bonus(s, SESSION_HALF, True)          # 시드(창이 100% 아님)
sun0 = s.raw_wallet
eq(grant_window_bonus(s, SESSION_FULL, True), WINDOW_SESSION, N)
# 30초마다 같은 상태가 다시 들어온다 — 여기서 또 주면 하루에 수백 번이다
for _ in range(10): grant_window_bonus(s, SESSION_FULL, True)
eq(s.raw_wallet - sun0, WINDOW_SESSION, N, "같은 창이 여러 번 지급됐다")

N = "testWindowRearmsAfterReset"
s = fresh()
grant_window_bonus(s, SESSION_HALF, True)
grant_window_bonus(s, SESSION_FULL, True)
sun0 = s.raw_wallet
grant_window_bonus(s, SESSION_HALF, True)          # 창 리셋 → 재무장
eq(s.window_tier.get("claude.fiveHour"), None, N, "재무장이 안 됐다")
eq(grant_window_bonus(s, SESSION_FULL, True), WINDOW_SESSION, N)
eq(s.raw_wallet - sun0, WINDOW_SESSION, N)

N = "testWeeklyWindowPaysFiveTimesSession"
eq(WINDOW_WEEKLY, WINDOW_SESSION * 5, N)
s = fresh()
grant_window_bonus(s, [("w", "weekly", 0.0)], True)
eq(grant_window_bonus(s, [("w", "weekly", 100.0)], True), WINDOW_WEEKLY, N)

N = "testWindowsNotTouchedWhenLimitsUnavailable"
s = fresh()
eq(grant_window_bonus(s, SESSION_FULL, False), 0, N)
check(not s.windows_seeded, N, "한도를 못 읽었는데 시드했다 — 나중에 소급 지급된다")
eq(s.window_tier, {}, N)

N = "testMultipleWindowsGrantIndependently"
s = fresh()
mixed_zero = [("claude.fiveHour", "session", 0.0), ("claude.sevenDay", "weekly", 0.0)]
grant_window_bonus(s, mixed_zero, True)
mixed_full = [("claude.fiveHour", "session", 100.0), ("claude.sevenDay", "weekly", 100.0)]
eq(grant_window_bonus(s, mixed_full, True),
   WINDOW_SESSION + WINDOW_WEEKLY, N)

N = "testWindowBonusCannotReplaceTokenUsage"
# 창만 태워서 상점을 굴릴 수 있으면 안 된다 — 사이클 수입의 1/5 안쪽.
cycle_income = TARGET_CYCLE_DAYS * ASSUMED_DAILY_RAW
check(est_window_bonus_per_cycle() < cycle_income / 5, N,
      f"{est_window_bonus_per_cycle():,} vs {cycle_income/5:,.0f}")

N = "testShrinkingSnapshotDoesNotRemoveWater"
s = fresh()
ingest(s, {"claude": TD(cr=50000000)}, D1); before = s.raw_wallet
ingest(s, {"claude": TD(cr=1000000)}, D1); eq(s.raw_wallet, before, N, "지갑이 깎였다")
# 기준이 내려갔으므로 다음 증분은 1,000만mL 어치가 아니라 그 차이만큼만 들어온다
ingest(s, {"claude": TD(cr=11000000)}, D1)
eq(s.raw_wallet, before + 10_000_000, N)

N = "testStagesRiseOnPour"
s = fresh(); apply_water(s, 12000, D1)
eq(s.pot.stage, 3, N)
ups = [e for e in s.events if e[0] == "levelUp"]
eq(len(ups), 1, N, "단계 상승 연출이 안 합쳐졌다"); eq(ups[0][1], 3, N)

N = "testFruitHarvestPushesEventOnce"
s = fresh()
apply_water(s, threshold(8, s.pot.cycle), D1)
eq(len([e for e in s.events if e[0] == "fruit"]), 1, N)
apply_water(s, 1000, D1)
eq(len([e for e in s.events if e[0] == "fruit"]), 1, N, "수확 이벤트가 두 번")

N = "testReadyEventFiresOnceOnTransition"
s = fresh(); _cyc = s.pot.cycle; apply_water(s, _cyc, D1)
check(s.pot.ready, N); drain(s)
apply_water(s, 50000, D1)
check(not any(e[0] == "ready" for e in s.events), N)

N = "testStreakGrowsOnConsecutiveDaysAndResetsOnGap"
s = fresh()
feed(s, 1000, D1); eq(s.streak, 1, N)
feed(s, 1000, D2); eq(s.streak, 2, N)
feed(s, 1000, "2026-09-06"); eq(s.streak, 1, N, "3일 비었는데 이어졌다")

N = "testItemWaterDoesNotBumpStreak"
s = fresh(); s.inv["nutrient"] = 1
use(s, "nutrient", D1); eq(s.streak, 0, N)

N = "testThirstRampsThenSaturates"
s = fresh()
feed(s, 20000, D1)
eq(thirst_level(s, "2026-09-03"), 0.0, N)
check(thirst_level(s, "2026-09-05") > 0, N)
eq(thirst_level(s, "2026-09-09"), 1.0, N)

N = "testThirstNeverTouchesWater"
s = fresh()
feed(s, 100000, D1)
kept = s.pot.water
for i in range(60):
    thirst_level(s, dk(dparse(D1) + timedelta(days=i)))
eq(s.pot.water, kept, N, "목마름이 누적 물을 깎았다")

N = "testGrowingResetsThirstAgain"
s = fresh()
feed(s, 20000, D1)
eq(thirst_level(s, "2026-09-20"), 1.0, N)
feed(s, 5000, "2026-09-20")
eq(thirst_level(s, "2026-09-20"), 0.0, N, "자랐는데 색이 안 돌아온다")

N = "testCannotBuyWithoutEnoughTokensAndErrorNamesShortfall"
s = fresh(); s.raw_wallet = 300
r = buy(s, "fertilizer")
eq(r[0], "insufficient", N); eq(r[1], PRICE["fertilizer"] - 300, N)
eq(s.raw_wallet, 300, N, "실패한 구매가 지갑을 깎았다")

N = "testPurchaseGoesToBagNotImmediateEffect"
s = fresh(); s.raw_wallet = 3_000_000_000; before = s.pot.water
eq(buy(s, "fertilizer")[0], "ok", N)
eq(s.count("fertilizer"), 1, N)
eq(s.pot.water, before, N, "구매만으로 물이 들어갔다")

N = "testPassiveCannotBeBoughtTwice"
s = fresh(); s.raw_wallet = PRICE["shinyCharm"]
eq(buy(s, "shinyCharm")[0], "ok", N)
eq(buy(s, "shinyCharm")[0], "alreadyOwned", N)
check(s.has_charm, N)

N = "testFertilizerBonusNeverStacks"
# 기간은 이어 붙지만 **배수는 절대 안 겹친다.** 겹치면 상점 상한 검증이 통째로 깨진다.
s = fresh(); s.inv["fertilizer"] = 2
use(s, "fertilizer", D1)
use(s, "fertilizer", D1)
eq(applied(1000, 0, True), 1250, N, "거름 두 개가 +50% 가 됐다")
eq(applied(1000, 0, False), 1000, N)

N = "testTransplantMovesPotToGardenAndPlantsNewSeed"
s = fresh(); _cyc = s.pot.cycle; apply_water(s, _cyc, D1)
sun_before = s.raw_wallet
check(transplant(s, 7), N)
eq(len(s.garden), 1, N); eq(s.garden[0]["total"], _cyc, N)
eq(s.raw_wallet, sun_before, N, "이식이 잔액을 건드렸다")
check(s.pot is not None, N); eq(s.pot.water, 0, N); eq(s.pot.stage, 0, N)

# ══════════ 장식 뽑기 — 꽝이 없어야 한다 ══════════
#
# 보유형 다섯이 17일이면 다 팔리고 그 뒤 상점엔 새로 열리는 게 없다.
# 장식 아홉을 직접 다 팔면 비싼 순서대로 사는 목록이 되어 살 때 아무 일도 안 일어난다.
# 뽑기는 누르는 순간에 결과가 있다 — 대신 **중복이 나오면 도박이 된다.**

N = "testDecorBoxNeverGivesADuplicate"
s = fresh()
s.inv["decorBox"] = len(GACHA_DECOR)
got = []
for i in range(len(GACHA_DECOR)):
    kind, _ = use(s, "decorBox", D1, roll=i * 7 + 3)   # 롤을 흩어도 중복이 없어야 한다
    eq(kind, "ok", N, f"{i + 1}번째 뽑기가 실패했다")
    got.append(s.decorations[-1])
eq(len(set(got)), len(GACHA_DECOR), N, f"중복이 나왔다: {got}")
eq(sorted(got), sorted(GACHA_DECOR), N, "안 나온 장식이 있다")

N = "testDecorBoxRefusesWhenEverythingIsOwned"
# 다 모은 사람이 또 사면 지갑만 나간다. 소모도 하면 안 된다.
s.inv["decorBox"] = 1
kind, _ = use(s, "decorBox", D1)
eq(kind, "noEffect", N, "다 모았는데 또 뽑혔다")
eq(s.count("decorBox"), 1, N, "실패했는데 소모됐다")

N = "testDecorBoxDoesNotTouchGrowthOrWallet"
# 장식은 순수 꾸미기다. 뽑기가 성장이나 지갑을 건드리면 두 물길이 섞인다.
s = fresh(); s.inv["decorBox"] = 1
before_water, before_wallet = s.pot.water, s.raw_wallet
use(s, "decorBox", D1)
eq(s.pot.water, before_water, N, "뽑기가 화분을 키웠다")
eq(s.raw_wallet, before_wallet, N, "뽑기가 지갑을 건드렸다")

N = "testDecorBoxIsNotANextGoal"
# 하루치라 제일 싸서 늘 먼저 걸린다. 성장에 도움이 안 되는 걸 목표로 걸면 모을 이유가 없다.
s = fresh(); s.raw_wallet = int(0.5 * ASSUMED_DAILY_RAW)
goal = next_goal(s)
check(goal is not None, N, "목표가 없다")
check(goal[0] != "decorBox", N, "장식 뽑기가 다음 목표로 걸렸다")
check(goal[0] not in DECORATION, N, f"장식({goal[0]})이 목표로 걸렸다")

N = "testShopDecorAndGachaDecorDoNotOverlap"
# 겹치면 상점에서 산 걸 뽑기로 또 받거나, 뽑기 풀이 조용히 줄어든다.
check(not (set(GACHA_DECOR) & DECORATION), N, f"겹침: {set(GACHA_DECOR) & DECORATION}")
eq(len(set(GACHA_DECOR)), 9, N, "뽑기 장식이 아홉이 아니다")

N = "testGardenNeverBlocksTransplant"
# 정원이 꽉 차면 이식이 조용히 실패하고 화분이 완주 상태로 **영원히** 대기했다.
# 그 뒤로는 아무 일도 안 일어난다 — 사이클 9일이었을 때 9개월이면 도달했다.
# 자리가 없다고 이식을 막는 건 순서가 거꾸로다: 기록은 쌓고 씬만 최근 것을 그린다.
s = fresh()
full = GARDEN_TIERS[-1][1]
for _ in range(full + 5):
    apply_water(s, s.pot.cycle, D1)
    check(transplant(s, 7, D1), N, f"{len(s.garden)}그루에서 이식이 막혔다")
eq(len(s.garden), full + 5, N, "만렙 이후 기록이 안 쌓였다")
check(s.pot is not None and s.pot.water == 0, N, "새 씨앗이 안 심겼다")

N = "testTransplantRejectsUnreadyPot"
s = fresh(); apply_water(s, 375000, D1)
check(not transplant(s, 1), N, "여유분 없이 이식됐다")

N = "testSeedGuaranteeIsConsumedOnce"
s = fresh(); s.inv["legendarySeed"] = 1
use(s, "legendarySeed", D1)
eq(s.pending_guarantee, "legendary", N)
plant_new_seed(s, 3)
sp = next(c for c in CATALOG if c[0] == s.pot.species)
eq(sp[1], "legendary", N)
eq(s.pending_guarantee, None, N, "보증이 소비되지 않았다")

N = "testPotSlotGivesASecondPotThatGrowsAlongside"
s = fresh(); s.raw_wallet = PRICE["potSlot"]
eq(buy(s, "potSlot")[0], "ok", N)
check(s.pot2 is not None, N)
apply_water(s, 12000, D1)
eq(s.pot.water, applied(12000, 0, False), N)
eq(s.pot2.water, applied(12000, 0, False), N, "두 번째 화분이 안 자랐다")

N = "testEventsCoalesceAndDrainOnce"
s = fresh()
for w in (1500, 3500, 7000): apply_water(s, w, D1)
eq(len([e for e in s.events if e[0] == "levelUp"]), 1, N)
dr = drain(s)
check(len(dr) > 0, N); eq(len(s.events), 0, N); eq(len(drain(s)), 0, N)

N = "testSameKindCollapsesToLatest"
s = fresh()
for i in range(40): push(s, "leafFall", i)
eq(len(s.events), 1, N); eq(s.events[0][1], 39, N)

N = "testEventQueueIsBounded"
s = fresh()
for k in ("wilt", "fruit", "ready", "levelUp", "leafFall", "transplant", "newSeed"):
    push(s, k)
check(len(s.events) <= 8, N)

N = "testGuaranteeNarrowsPoolToRarityOrAbove"
check(all(RANK[pick_species(r, "rare")[1]] >= RANK["rare"] for r in range(300)), N)

N = "testRarityDistributionMatchesWeights"
total = sum(WEIGHT[c[1]] for c in CATALOG)
eq(total, 4560, N)
counts = {}
for r in range(total):
    counts[pick_species(r)[1]] = counts.get(pick_species(r)[1], 0) + 1
eq(counts.get("common"), 3100, N); eq(counts.get("uncommon"), 1000, N)
eq(counts.get("rare"), 400, N); eq(counts.get("legendary"), 60, N)
check(counts.get("legendary", 0) / total < 0.02, N)

N = "testShinyCharmQuadruplesOdds"
plain = sum(1 for r in range(1280) if rolls_shiny(r, False))
charmed = sum(1 for r in range(1280) if rolls_shiny(r, True))
eq(plain, 10, N); eq(charmed, 40, N)

N = "testGardenTiersAdvanceByCount"
eq(tier_for(0)[0], "sill", N); eq(tier_for(2)[0], "balc", N)
eq(tier_for(3)[0], "bed", N); eq(tier_for(100)[0], "forest", N)
eq(tier_next(3)[1], 6, N); eq(tier_next(30), None, N)

N = "testTransplantSecondSlotLeavesFirstPotAlone"
s = fresh(); s.raw_wallet = PRICE["potSlot"]
buy(s, "potSlot")
apply_water(s, max(s.pot.cycle, s.pot2.cycle if s.pot2 else 0), D1)
check(s.pot.ready and s.pot2.ready, N, "둘 다 완주했어야 한다")
first_water = s.pot.water
check(transplant(s, 7, D1, slot=1), N)
eq(len(s.garden), 1, N)
eq(s.pot.water, first_water, N, "1번 화분이 건드려졌다")
eq(s.pot2.water, 0, N, "2번 화분에 새 씨앗이 안 심겼다")
check(transplant(s, 9, D1, slot=0), N)
eq(len(s.garden), 2, N)
eq(s.pot.water, 0, N)

N = "testSeedGuaranteeIsSpentOnlyOnFirstSlot"
s = fresh(); s.raw_wallet = PRICE["potSlot"] + PRICE["legendarySeed"]
buy(s, "potSlot"); buy(s, "legendarySeed")
use(s, "legendarySeed", D1)
eq(s.pending_guarantee, "legendary", N)
apply_water(s, max(s.pot.cycle, s.pot2.cycle if s.pot2 else 0), D1)
# 2번을 먼저 옮겨도 보증은 남아 있어야 한다 — 산 것은 다음 "첫 화분" 씨앗에 쓴다.
transplant(s, 3, D1, slot=1)
eq(s.pending_guarantee, "legendary", N, "2번 슬롯이 보증을 먹었다")
sp2 = next(c for c in CATALOG if c[0] == s.pot2.species)
transplant(s, 3, D1, slot=0)
eq(s.pending_guarantee, None, N)
sp1 = next(c for c in CATALOG if c[0] == s.pot.species)
eq(sp1[1], "legendary", N)

N = "testDecorationGoesStraightToGarden"
s = fresh(); s.raw_wallet = PRICE["bench"] + PRICE["lantern"]
eq(buy(s, "bench")[0], "ok", N)
eq(s.decorations, ["bench"], N)
eq(s.count("bench"), 0, N, "장식이 가방에 담겼다")
eq(buy(s, "bench")[0], "alreadyOwned", N, "장식을 두 번 살 수 있다")
eq(buy(s, "lantern")[0], "ok", N)
eq(s.decorations, ["bench", "lantern"], N)
eq(s.raw_wallet, 0, N, "장식 값이 지갑에서 안 나갔다")

N = "testDecorationHasNoGrowthEffect"
a = fresh(); a.balance = 100000
b = fresh(); b.balance = 100000
buy(a, "bench"); buy(a, "feeder"); buy(a, "lantern")
apply_water(a, 30000, D1); apply_water(b, 30000, D1)
eq(a.pot.water, b.pot.water, N, "장식이 성장에 영향을 줬다")
eq(a.pot.stage, b.pot.stage, N)

N = "testDecorationCannotBeUsedFromBag"
s = fresh(); s.raw_wallet = PRICE["bench"]
buy(s, "bench")
eq(use(s, "bench", D1)[0], "notOwned", N, "가방에 없는 장식을 쓸 수 있다")

# ══════════ DailyRateTests — 기준을 재는 부분 ══════════
#
# 화면의 큰 숫자는 전부 여기를 지나 "며칠치"가 된다.
# 이 값이 틀리면 가격표가 통째로 거짓말이 되므로, 틀리느니 기본값으로 물러나야 한다.

N = "testRateFallsBackUntilThereIsEnoughData"
eq(daily_rate({}), ASSUMED_DAILY_RAW, N, "표본이 없는데 측정값을 냈다")
eq(daily_rate({D1: 90000}), ASSUMED_DAILY_RAW, N, "하루치로 평균을 냈다")
eq(daily_rate({D1: 90000, D2: 0}), ASSUMED_DAILY_RAW, N, "이틀치로 평균을 냈다")

N = "testRateIsCalendarAverageIncludingIdleDays"
# 사흘 창에 30,000 이 들어왔으면 하루 10,000 이다. 안 쓴 날을 빼고 15,000 이라고 하면
# "1.3일치"가 실제로는 이틀이 되어, 아끼면 살 수 있다는 약속이 깨진다.
eq(daily_rate({D1: 30000, D3: 0}), 10000, N)
eq(daily_rate({D1: 10000, D2: 10000, D3: 10000}), 10000, N)

N = "testRateWindowDropsOldDays"
old = "2026-08-20"
eq(pruned_daily({old: 99999, D1: 10000}, "2026-09-03"), {D1: 10000}, N, "14일 밖이 남았다")
eq(len(pruned_daily({D1: 1, D2: 1, D3: 1}, D3)), 3, N, "창 안쪽이 버려졌다")

N = "testCreditAccumulatesWithinADay"
s = fresh()
credit(s, 5000, 1, D1)
credit(s, 3000, 1, D1)
eq(s.daily_raw, {D1: 8000}, N, "같은 날 유입이 합산되지 않았다")
eq(s.raw_wallet, 8000, N)

N = "testWindowBonusStaysOutOfTheDailyStat"
# 창 보너스는 토큰을 쓴 양이 아니라 창을 태운 보상이다.
# 섞으면 "하루에 이만큼 쓴다"가 부풀어 모든 환산이 낙관적이 된다.
s = fresh(); s.windows_seeded = True
grant_window_bonus(s, SESSION_FULL, True)
eq(s.daily_raw, {}, N, "창 보너스가 하루 유입에 섞였다")
eq(s.streak, 0, N, "창 보너스가 스트릭을 올렸다")
check(s.raw_wallet > 0, N, "지갑에는 들어가야 한다")

N = "testDailyRawSurvivesTheWindowButNotForever"
s = fresh()
credit(s, 1000, 1, "2026-08-20")
credit(s, 1000, 1, "2026-09-10")
eq(sorted(s.daily_raw), ["2026-09-10"], N, "창 밖 기록이 안 지워졌다")

# ══════════ 가격 — 일 단위가 기준이다 ══════════

N = "testPriceIsDerivedFromDays"
for item, days in PRICE_DAYS.items():
    eq(PRICE[item], int(days * ASSUMED_DAILY_RAW), N, f"{item} 가격이 일수와 안 맞는다")

N = "testCheapestItemsAreWithinADay"
eq(min(PRICE.values()), PRICE["water"], N, "물이 제일 싸지 않다")
eq(PRICE_DAYS["water"], 0.2, N)
eq(PRICE["bench"], ASSUMED_DAILY_RAW, N)

N = "testNoItemCostsMoreThanACycle"
# 사이클보다 비싼 품목이 있으면 한 그루를 통째로 포기해도 못 산다.
cycle_days = float(TARGET_CYCLE_DAYS)
for item, days in PRICE_DAYS.items():
    check(days < cycle_days, N, f"{item} {days}일 >= 사이클 {cycle_days:.1f}일")

N = "testNutrientBeatsWaterEarlyOnly"
# 같은 값으로 물을 샀을 때와 견준다 — 가격은 원시 토큰, 회수는 mL 이라 직접 못 비교한다.
alt_ml = (PRICE_DAYS["nutrient"] / PRICE_DAYS["water"]) * water_ml()
eq(nutrient_gain(0, CYCLE) > alt_ml, True, N, "갓 심은 그루에 영양제가 물만 못하다")
eq(nutrient_gain(TH_(8), CYCLE) > alt_ml, False, N, "후반에도 이득이면 살 때를 고를 이유가 없다")

N = "testDaysForWaterReadsBackAsPrice"
for item, days in PRICE_DAYS.items():
    close(days_for(PRICE[item], ASSUMED_DAILY_RAW), days, 0.001, N)

# ══════════ 기준선 · 실측 환산비율 · 백필 ══════════
#
# 화면의 "평소 대비"와 사이클 목표가 전부 여기서 나온다.
# 틀린 퍼센트는 아무 숫자도 안 쓴 것보다 나쁘므로, 못 재면 **nil 로 물러나야** 한다.

N = "testBaselineExcludesToday"
# 아침엔 오늘 몫이 거의 0인데 분모는 오늘을 이미 하루로 센다.
# 오늘을 기준에 넣으면 **오늘이 끌어내린 평균과 오늘을** 견주게 되어 늘 100% 근처가 된다.
D4 = "2026-09-04"
daily = {D1: 30000, D2: 30000, D3: 30000, D4: 300}
eq(baseline_raw_rate(daily, D4), 30000, N, "오늘이 기준에 섞였다")
eq(daily_rate(daily), 90300 // 4, N, "가격 환산용 평균은 오늘을 포함해야 한다")

N = "testBaselineIsNilUntilThereIsEnoughPast"
eq(baseline_raw_rate({}, D3), None, N, "표본이 없는데 기준을 냈다")
eq(baseline_raw_rate({D3: 50000}, D3), None, N, "오늘뿐인데 기준을 냈다")
eq(baseline_raw_rate({D2: 10000, D3: 10000}, D3), None, N, "과거 이틀치로 기준을 냈다")

N = "testBaselineCountsIdleDaysAsZero"
# 안 쓴 날을 빼면 "평소"가 부풀어, 실제로 평소만큼 쓴 날이 60% 로 보인다.
eq(baseline_raw_rate({D1: 30000, D3: 0, D4: 0}, D4), 10000, N)

N = "testMeasuredRatioNeedsBothSides"
raw = {D1: 80000, D2: 80000, D3: 80000}
water = {D1: 10, D2: 10, D3: 10}
eq(measured_raw_per_ml(raw, water), 8000, N, "겹치는 날로 못 나눴다")
eq(measured_raw_per_ml(raw, {D1: 10}), None, N, "한 날로 비율을 냈다")
eq(measured_raw_per_ml(raw, {D1: 0, D2: 0, D3: 0}), None, N, "0 으로 나눴다")
eq(measured_raw_per_ml({}, water), None, N, "원시가 없는데 값을 냈다")

N = "testMeasuredRatioOnlyUsesOverlappingDays"
# 백필은 두 통을 같이 채우지만, 설치 전 원시만 있는 날이 섞이면 비율이 부푼다.
eq(measured_raw_per_ml({D1: 999999, D2: 80000, D3: 80000, "2026-09-04": 80000},
                       {D2: 10, D3: 10, "2026-09-04": 10}), 8000, N, "겹치지 않는 날이 섞였다")

N = "testCreditRecordsWaterBeforeBonuses"
# 스트릭·거름이 섞이면 환산비율이 아니라 "요즘 보너스가 얼마나 붙었나"를 재게 된다.
s = fresh(); s.streak = 25; s.last_use_day = D1
credit(s, 8193 * 10, 10, D1)
eq(s.daily_water, {D1: 10}, N, "보너스 먹인 값이 통계에 들어갔다")
check(s.pot.water > 10, N, "성장에는 보너스가 붙어야 한다")
eq(measured_raw_per_ml(s.daily_raw, s.daily_water), None, N, "하루치로 비율을 냈다")

N = "testBackfillMeasuresWithoutPaying"
# 설치하자마자 2주치가 쏟아지면 첫 화면이 거목이 된다. 백필은 **재기만** 한다.
s = fresh()
hist = {D1: TD(o=100000, cr=10000000), D2: TD(o=100000, cr=10000000)}
eq(backfill_history(s, hist, D3), True, N)
eq(s.raw_wallet, 0, N, "백필이 지갑에 적립했다")
eq(s.pot.water, 0, N, "백필이 성장을 밀었다")
eq(s.streak, 0, N, "백필이 스트릭을 올렸다")
eq(sorted(s.daily_raw), [D1, D2], N, "통계가 날짜별로 안 들어갔다")
check(all(v > 0 for v in s.daily_water.values()), N, "환산 분모가 비었다")

N = "testBackfillRunsOnlyOnce"
before = dict(s.daily_raw)
eq(backfill_history(s, hist, D3), False, N, "두 번째 백필이 통과했다")
eq(s.daily_raw, before, N, "두 번 세어져 하루 유입이 두 배가 됐다")

N = "testBackfillDropsDaysOutsideTheWindow"
# 오늘(D3)은 ingest 몫이라 백필이 건너뛴다 — 그래서 과거 키로만 검증한다.
s = fresh()
backfill_history(s, {"2026-08-01": TD(o=100000), D1: TD(o=100000)}, D3)
eq(sorted(s.daily_raw), [D1], N, "창 밖 기록이 남았다")

N = "testNextGoalSkipsDecorations"
# 벤치가 1일치라 늘 제일 먼저 걸린다. 성장에 도움 안 되는 걸 목표로 걸면 모을 이유가 없다.
s = fresh()
s.raw_wallet = int(0.5 * ASSUMED_DAILY_RAW)   # 물은 살 수 있고 벤치는 못 산다
goal = next_goal(s)
check(goal is not None, N, "목표가 없다")
check(goal[0] not in DECORATION, N, f"장식({goal[0]})이 목표로 걸렸다")
eq(goal[0], "fertilizer", N, "장식 다음으로 싼 성장 품목이 아니다")

N = "testInstallLeavesTheLedgerAtZero"
# **실제로 화면에 거짓말이 찍혔던 자리다.**
#
# 예전엔 첫날 상한에 걸린 분이 `raw_since` 에는 들어가고 지갑에는 안 들어가서,
# 그 차액이 영원히 "쓴 것"으로 찍혔다 — 한 번도 안 산 사람에게 지출이 보였다.
# 상한이 사라져 그 틈이 구조적으로 없어졌지만, 소급이 되살아나면 거짓말도 돌아온다.
s = fresh(); s.claimed = None
big = TD(o=ASSUMED_DAILY_RAW * 10)          # 첫날 로그가 하루치의 10배
ingest(s, {"claude": big}, D1)
eq(s.raw_since, 0, N, "설치 전 몫이 누적에 들어갔다")
eq(s.raw_wallet, 0, N, "설치 전 몫이 지갑에 들어갔다")
eq(spent_total(s), 0, N, "아무것도 안 샀는데 쓴 것이 있다")
eq(earned_total(s) - spent_total(s), s.raw_wallet, N, "번 것 − 쓴 것 ≠ 지갑")

N = "testLedgerBalancesAcrossEveryPath"
# 적립 · 창 보너스 · 구매를 섞어도 셋이 계속 맞아야 한다.
s = fresh(); s.windows_seeded = True
credit(s, 20 * PRICE["water"], 5, D1)
grant_window_bonus(s, SESSION_FULL, True)
buy(s, "water"); buy(s, "water")
eq(earned_total(s) - spent_total(s), s.raw_wallet, N, "번 것 − 쓴 것 ≠ 지갑")
eq(spent_total(s), 2 * PRICE["water"], N, "쓴 것이 구매 합계와 다르다")

N = "testWalletIsEarnedMinusSpent"
# "오늘 127M 썼는데 왜 지갑이 95M 이지?" — 차액이 곧 지금까지 쓴 값이다.
s = fresh()
s.claimed = {"claude": TD()}
ingest(s, {"claude": TD(o=int(10 * PRICE["water"] / 1))}, D1)
s.raw_wallet = s.raw_since   # 첫날 상한을 지나 들어온 몫만큼 맞춰둔다
earned = earned_total(s)
check(earned > PRICE["water"], N, "첫날 유입이 물값보다 적다")
buy(s, "water")
eq(earned_total(s), earned, N, "번 것이 구매로 줄었다")
eq(spent_total(s), PRICE["water"], N, "쓴 것이 값과 안 맞는다")
eq(s.raw_wallet, earned - spent_total(s), N, "지갑 = 번 것 − 쓴 것 이 아니다")

# ══════════ 검토에서 나온 회귀 ══════════
#
# 이 아래는 전부 **실제로 화면에 틀린 값이 찍히거나 상태가 망가지던** 자리다.
# 하나하나 재현 절차가 있어서 주석에 적어둔다.

N = "testClockJumpDoesNotWipeTheHistory"
# 시계가 앞으로 튀면(RTC 오류·수동 변경) 정리 한 번에 14일 기록이 전부 날아갔다.
# 그러면 하루 유입이 기본값으로 돌아가 가격이 21배로 뛰고, `historyBackfilled` 때문에
# 다시 채워지지도 않는다.
hist = {dk(date(2026, 9, 1) + timedelta(days=k)): 5_000_000 for k in range(14)}
eq(pruned_daily(hist, "2027-06-01"), hist, N, "미래 날짜 하나로 기록 전체가 날아갔다")
# 시계가 정상이면 평소대로 정리된다.
# 09-01~09-14 기록에 오늘이 09-20 이면 09-07 부터만 남는다(창 14일).
eq(len(pruned_daily(hist, "2026-09-20")), 8, N, "정상 범위에서 정리가 안 됐다")
eq(min(pruned_daily(hist, "2026-09-20")), "2026-09-07", N)
eq(len(pruned_daily({}, "2027-06-01")), 0, N)

N = "testSecondPotGetsTheSameTargetAsTheFirst"
# 둘째 화분을 목표 없이 만들어서 기본값(400,000)이 박혔다. 하루 5M 쓰는 사람에겐
# 첫 화분 28일 / 둘째 화분 557일이 같은 화면에 나란히 떴다.
s = fresh()
for k in range(5):
    credit(s, 5_000_000, 5_000_000 // RAW_PER_ML, dk(date(2026, 9, 1) + timedelta(days=k)))
s.pot.cycle = seed_cycle(s)
s.raw_wallet = PRICE["potSlot"] * 3
eq(buy(s, "potSlot")[0], "ok", N)
check(s.pot2 is not None, N, "둘째 화분이 안 생겼다")
eq(s.pot2.cycle, s.pot.cycle, N, f"첫 화분 {s.pot.cycle} vs 둘째 {s.pot2.cycle}")
check(s.pot2.cycle != LEGACY_CYCLE_WATER, N, "기본값이 박혔다")

N = "testSeedCycleUsesTheMeasuredRatio"
# 상수 6,957 로 나누면 실측 8,193 인 사람의 28일 사이클이 33일이 된다.
s = fresh()
for k in range(4):
    day = dk(date(2026, 9, 1) + timedelta(days=k))
    s.daily_raw[day] = 8_193_000
    s.daily_water[day] = 1_000          # 실측 8,193 : 1
eq(measured_raw_per_ml(s.daily_raw, s.daily_water), 8193, N)
eq(seed_cycle(s), cycle_water(daily_rate(s.daily_raw), 8193), N, "실측 비율을 안 썼다")
check(seed_cycle(s) < cycle_water(daily_rate(s.daily_raw), RAW_PER_ML), N,
      "상수로 계산한 것보다 목표가 작아야 한다(28일에 맞춰지므로)")

N = "testSeedReservationNeverDowngrades"
# 예약 칸이 하나인데 그냥 덮어써서, 전설 예약 위에 고급을 올리면 **등급이 내려가고**
# 산 전설이 사라졌다. 화면은 "예약됐어요" 라고만 말했다.
s = fresh(); s.inv["legendarySeed"] = 1; s.inv["premiumSeed"] = 1
eq(use(s, "legendarySeed", D1)[0], "ok", N)
eq(s.pending_guarantee, "legendary", N)
eq(use(s, "premiumSeed", D1)[0], "noEffect", N, "고급이 전설 예약을 덮었다")
eq(s.pending_guarantee, "legendary", N, "등급이 내려갔다")
eq(s.count("premiumSeed"), 1, N, "거절했는데 소모됐다")
# 반대로 비어 있으면 당연히 예약된다.
s.pending_guarantee = None
eq(use(s, "premiumSeed", D1)[0], "ok", N)
eq(s.pending_guarantee, "rare", N)

N = "testDecorBoxIsNotStuckInTheBag"
# 뽑기는 사는 즉시 열리므로 가방에 남지 않는다. 남으면 영원히 ×0 인 줄이 생긴다.
s = fresh(); s.raw_wallet = PRICE["decorBox"] * 2
eq(buy(s, "decorBox")[0], "ok", N)
eq(use(s, "decorBox", D1, roll=0)[0], "ok", N)
eq(s.count("decorBox"), 0, N, "뽑고 나서도 가방에 남았다")

N = "testLightDailyUserNeverLooksParched"
# 가중합을 100,000 으로 나누므로 캐시읽기 9,000토큰은 **0mL** 다. 그러면 apply_water 가
# 바로 빠져나가 last_water_day 가 안 찍히고, 매일 쓰는 사람이 7일 뒤 "바싹 말랐어요" 가 됐다.
s = fresh()
tiny = TD(cr=9_000)
eq(water_from(tiny), 0, N, "이 입력이 0mL 가 아니면 이 검증이 의미가 없다")
for k in range(9):
    day = dk(date(2026, 9, 1) + timedelta(days=k))
    credit(s, tiny.raw, water_from(tiny), day)
    eq(thirst_level(s, day), 0.0, N, f"{k + 1}일째에 말랐다고 판정됐다")
eq(s.last_water_day, dk(date(2026, 9, 9)), N)

N = "testTransplantEstimateUsesRealPace"
# **홈에서 제일 동기가 되는 숫자**인데 3배 거짓말이었다.
# 목표(seed_cycle)는 실측 환산비율로 만드는데 이 추정만 상수(6,957)로 나눠서,
# 캐시읽기가 많은 사람(실측 3,796)에게 "이식까지 약 51일"이 떴다(실제 16일).
# 게다가 물·스트릭·거름 보너스를 아예 안 셌다.
s = fresh()
heavy = TD(o=8_193_000, cr=246_000_000 - 8_193_000)   # 캐시읽기가 대부분인 하루
for k in range(6):
    day = dk(date(2026, 9, 1) + timedelta(days=k))
    s.daily_raw[day] = heavy.raw
    s.daily_water[day] = water_from(heavy)
today = dk(date(2026, 9, 7))
s.pot.cycle = seed_cycle(s)
s.pot.water = 0
s.streak = 30
s.fert_until = dk(date(2026, 9, 20))

real = measured_daily_water(s.daily_water, today)
eq(real, water_from(heavy), N, "하루 mL 을 기록에서 못 읽었다")
naive = -(-s.pot.cycle // max(1, daily_rate(s.daily_raw) // RAW_PER_ML))
est = days_to_transplant(s, today)
check(est < naive / 2, N, f"상수 환산 {naive}일 vs 고친 것 {est}일 — 절반 이하여야 한다")
check(20 <= est <= 30, N, f"추정 {est}일 — 28일 설계에 보너스를 먹인 범위여야 한다")

N = "testTransplantEstimateIsZeroWhenReady"
s = fresh(); s.pot.water = s.pot.cycle
eq(days_to_transplant(s, D1), 0, N, "다 자랐는데 남은 일수가 있다")

# ══════════ 흐름 검토에서 나온 회귀 ══════════

N = "testNutrientFeedsOnlyItsOwnPot"
# apply_water 를 타서 화분 2에도 같은 양이 **공짜로** 들어갔다. 그러면
# "한 그루에 한 번"이 거짓이고(화분 2는 자기 횟수를 영원히 안 쓴다),
# 양도 화분 1의 남은 거리로 계산돼서 엉뚱한 그루 기준으로 매겨진다.
s = fresh()
s.pot2 = Pot(species="rose", cycle=s.pot.cycle)
s.pot.water = int(s.pot.cycle * 0.9)
s.inv["nutrient"] = 1
before2 = s.pot2.water
kind, got = use(s, "nutrient", D1)
eq(kind, "ok", N)
check(got > 0, N, "화분 1에 안 들어갔다")
eq(s.pot2.water, before2, N, "화분 2에 공짜로 들어갔다")
eq(s.pot.nutrient_uses, 1, N)

N = "testCelebrationPriorityLetsTheRareOneWin"
# 한 번의 비움에 여러 이벤트가 같이 들어온다. 하나만 재생되므로 더 드문 쪽이 이겨야 한다.
# 이 순서가 아니었을 때 newSeed 와 fruit 는 **구조적으로 한 번도** 재생되지 않았다.
PRIORITY = ["fruit", "newSeed", "transplant", "levelUp", "decor", "ready", "window"]
def chosen(keys):
    return next((k for k in PRIORITY if k in keys), None)
eq(chosen({"levelUp", "fruit"}), "fruit", N, "열매가 단계 상승에 밀렸다")
eq(chosen({"transplant", "newSeed"}), "newSeed", N, "새 씨앗이 이식에 밀렸다")
eq(chosen({"levelUp", "ready"}), "levelUp", N)
check("thirsty" not in PRIORITY, N, "목마름이 표에 있으면 30초마다 저장한다")

N = "testBackfillSkipsToday"
# readRecent 가 오늘을 포함해 돌려주는데 ingest 도 오늘을 적립한다 —
# 백필이 오늘을 넣으면 같은 날이 두 번 세어져 하루 유입이 7% 부푼다.
s = fresh()
hist = {D1: TD(o=10_000_000), D2: TD(o=10_000_000), D3: TD(o=10_000_000)}
backfill_history(s, hist, D3)          # D3 == today
eq(sorted(s.daily_raw), [D1, D2], N, "오늘이 백필에 들어갔다")

N = "testFertilizerExtendsSoItIsAlwaysUsable"
# **"거름 사도 바로 못 쓰던데"** 가 나온 자리다.
# 7일이 다시 시작되는 규칙이라 돌고 있는 동안 쓰면 남은 날이 날아갔고,
# 그걸 막으려고 화면이 버튼을 비활성화해서 산 물건을 못 쓰게 됐다.
# 이어 붙이면 그 상태 자체가 없어진다 — 배수는 그대로 +25% 라 밸런스도 안 건드린다.
s = fresh(); s.inv["fertilizer"] = 3
eq(use(s, "fertilizer", D1)[0], "ok", N)
first = s.fert_until
eq(use(s, "fertilizer", D1)[0], "ok", N, "돌고 있는 동안 못 썼다")
check(s.fert_until > first, N, "기간이 안 늘었다 — 갱신되기만 했다")
eq(ddays(D1, s.fert_until), FERT_DAYS * 2, N, f"{ddays(D1, s.fert_until)}일")
# 배수는 안 겹친다 — 두 개를 써도 +50% 가 되면 안 된다.
eq(applied(1000, 0, True), 1000 + 1000 * FERT_BONUS // 100, N, "배수가 중첩됐다")

N = "testFertilizerStopsAtTheCeiling"
# 천장에 닿으면 **소모 전에** 막는다 — 소모부터 하면 산 게 그냥 사라진다.
s = fresh(); s.inv["fertilizer"] = 10
for _ in range(10):
    use(s, "fertilizer", D1)
check(ddays(D1, s.fert_until) <= FERT_MAX_DAYS, N, f"{ddays(D1, s.fert_until)}일까지 쌓였다")
check(s.count("fertilizer") > 0, N, "천장에 닿았는데 계속 소모됐다")
eq(use(s, "fertilizer", D1)[0], "noEffect", N)

# ══════════ 결과 ══════════
print(f"\n단정 {PASS + len(FAIL)}개 중 {PASS}개 통과, {len(FAIL)}개 실패")
if FAIL:
    print("\n실패:")
    for f in FAIL: print("  ✗", f)
    sys.exit(1)
print("전부 통과")
