# -*- coding: utf-8 -*-
"""PlantEngine.swift 를 그대로 포팅해 테스트 본문을 실제로 돌린다.

목적은 알고리즘 검증이다 — 문법은 tree-sitter 가 봤고, 여기서는
멱등성·단계 루프·하루 1회 감소·상점 흐름·이벤트 합침이 실제로 그렇게 도는지 본다.
Swift 쪽을 고치면 이 파일도 같이 고쳐야 한다(의도적 중복).
"""
from dataclasses import dataclass, field
from datetime import date, timedelta

# ── PlantBalance ────────────────────────────────────────────────
W_OUT, W_IN, W_CW, W_CR = 500, 100, 125, 10
TOKENS_PER_ML = 1000
# 단계 임계값은 **비율**이다. 절대 mL 로 박으면 하루 5M 쓰는 사람은 1년 반 동안
# 씨앗만 보고, 400M 쓰는 사람은 일주일에 한 그루씩 뽑는다.
STAGE_FRACTIONS = [0, 0.00375, 0.0125, 0.03, 0.0675, 0.13, 0.235, 0.3925, 0.6175, 0.9375]
STAGE_COUNT = len(STAGE_FRACTIONS)
TARGET_CYCLE_DAYS = 28
MIN_CYCLE_WATER = 7_000
MAX_CYCLE_WATER = 2_000_000
LEGACY_CYCLE_WATER = 400_000
# 하루에 줄 수 있는 횟수. mL 로 세면 화면에 못 쓴다 — "오늘 3/5"가 읽힌다.
DAILY_WATER_USES = 2
# 영양제는 비례 품목이라 횟수로 못 막는다(갓 심었을 때 한 개가 자동 성장 5.6일치).
# 한 그루에 한 번으로 두면 "언제 쓰느냐"가 진짜 고민이 된다.
NUTRIENT_PER_PLANT = 1
THIRSTY_AFTER, PARCHED_AFTER = 3, 7
FERT_BONUS, FERT_DAYS = 25, 7
# 이어 붙이기의 천장. 없으면 지갑이 남는 사람이 1년치를 쌓아놓고 잊는다.
FERT_MAX_DAYS = 21
# 한도 창 소진 보상 — 만료되는 자원을 남는 것으로 바꾼다. 단위는 mL.
WINDOW_SESSION, WINDOW_WEEKLY = 10_000_000, 50_000_000
ASSUMED_SESSION_WINDOWS, ASSUMED_WEEKLY_WINDOWS = 11, 3
FIRST_DAY_CREDIT_DAYS = 2


def first_day_credit(cycle):
    # 상한도 목표에 비례해야 한다 — 고정값이면 적게 쓰는 사람의 첫날이 사이클을 통째로 채운다.
    return max(1, cycle * FIRST_DAY_CREDIT_DAYS // TARGET_CYCLE_DAYS)


def first_day_raw_cap(daily_raw):
    return max(1, daily_raw * FIRST_DAY_CREDIT_DAYS)

# 하루 유입 — 화면의 "며칠치" 환산의 분모.
# 상수로 박지 않고 앱이 직접 재는 값이다. 사람마다 하루 유입이 10배씩 달라서,
# 남의 평균으로 환산하면 "1.3일치"가 거짓말이 된다.
DAILY_WINDOW = 14
DAILY_MIN_DAYS = 3

# 두 물길. 쓴 토큰 하나가 두 곳으로 간다.
#   가중 환산 mL ─▶ 화분. 저절로 자란다
#   원시 토큰   ─▶ 지갑. 물·거름·영양제를 산다
# 둘은 서로 뺏지 않는다.
RAW_PER_ML = 6957
ASSUMED_DAILY_RAW = 105_000_000


def daily_water_from_tokens():
    return ASSUMED_DAILY_RAW // RAW_PER_ML


def water_ml(daily_raw=None):
    # 하루치 지갑을 통째로 물에 쏟으면 하루 자동 성장만큼 더 자란다 = 최대 가속 2배.
    # 값도 하루치의 1/5 이라 누구에게나 천장이 2배다.
    if daily_raw is None: daily_raw = ASSUMED_DAILY_RAW
    return max(1, daily_raw // RAW_PER_ML // 5)


@dataclass
class TD:
    i: int = 0
    o: int = 0
    cw: int = 0
    cr: int = 0

    @property
    def raw(self): return self.i + self.o + self.cw + self.cr
    @property
    def is_zero(self): return self.raw == 0

    def __sub__(self, r): return TD(self.i - r.i, self.o - r.o, self.cw - r.cw, self.cr - r.cr)
    def __add__(self, r): return TD(self.i + r.i, self.o + r.o, self.cw + r.cw, self.cr + r.cr)

    def clamped(self):
        return TD(max(0, self.i), max(0, self.o), max(0, self.cw), max(0, self.cr))


def water_from(d):
    c = d.clamped()
    return (c.o * W_OUT + c.i * W_IN + c.cw * W_CW + c.cr * W_CR) // (TOKENS_PER_ML * 100)


def seed_cycle(s):
    """새 그루 목표를 **한 곳에서** 계산한다 + 환산비율은 실측값을 쓴다."""
    ratio = measured_raw_per_ml(s.daily_raw, s.daily_water) or RAW_PER_ML
    return cycle_water(daily_rate(s.daily_raw), ratio)


def cycle_water(daily_raw, raw_per_ml=None):
    """이 사람 속도로 4주짜리 목표를 만든다. **심을 때 한 번** 잡고 끝까지 안 움직인다.

    사이클 중간에 목표가 따라 움직이면 많이 쓴 날 목표도 같이 늘어나서
    "쓰면 자란다"가 깨진다.
    """
    per_day = max(1, daily_raw // max(1, raw_per_ml or RAW_PER_ML))
    return min(MAX_CYCLE_WATER, max(MIN_CYCLE_WATER, per_day * TARGET_CYCLE_DAYS))


def threshold(idx, cycle):
    if idx < 0: return 0
    if idx >= STAGE_COUNT: return cycle
    return int(STAGE_FRACTIONS[idx] * cycle)


def stage_index(ml, cycle):
    idx = 0
    for k in range(STAGE_COUNT):
        if ml >= threshold(k, cycle):
            idx = k
    return idx


def next_threshold(idx, cycle):
    if idx + 1 < STAGE_COUNT: return threshold(idx + 1, cycle)
    if idx == STAGE_COUNT - 1: return cycle
    return None


def streak_bonus(days): return min(max(0, days), 10)


def applied(ml, streak_days, fert):
    bonus = streak_bonus(streak_days) + (FERT_BONUS if fert else 0)
    return ml + (ml * bonus) // 100


def est_window_bonus_per_cycle():
    return ASSUMED_SESSION_WINDOWS * WINDOW_SESSION + ASSUMED_WEEKLY_WINDOWS * WINDOW_WEEKLY


# ── Shop ────────────────────────────────────────────────────────
# 값을 **일**로 정하고 mL 은 파생값으로 둔다. 사용자는 사이클이 몇 일인지 모르니
# "사이클 대비 몇 %"로는 가격을 정당화할 수 없다 — "며칠 안 부으면 살 수 있나"가 곧 값이다.
PRICE_DAYS = dict(water=0.2, bench=1, decorBox=1, fertilizer=1.5, feeder=2, nutrient=1.5,
                  lantern=3, premiumSeed=4, legendarySeed=7, potSlot=10, shinyCharm=10)
PRICE = {k: int(v * ASSUMED_DAILY_RAW) for k, v in PRICE_DAYS.items()}


def price_for(item, daily_raw):
    return int(PRICE_DAYS[item] * daily_raw)
DECORATION = {"bench", "feeder", "lantern"}
# 뽑기로만 나오는 장식 아홉. 아트의 출처는 `verify/gen_decor.py` 다.
GACHA_DECOR = ["birdbath", "gnome", "windmill", "mailbox", "steppingstones",
               "fence", "mushroom", "arch", "cat"]
PASSIVE = {"shinyCharm", "potSlot"} | DECORATION
SEED_GUARANTEE = dict(premiumSeed="rare", legendarySeed="legendary")
REPOT_REDUCE = 10


def nutrient_gain(cur, cycle):
    return (max(0, cycle - cur) * REPOT_REDUCE) // 100


# ── Species ─────────────────────────────────────────────────────
RANK = dict(common=0, uncommon=1, rare=2, legendary=3)
WEIGHT = dict(common=620, uncommon=250, rare=100, legendary=30)
CATALOG = [
    ("dandelion", "common", "low"), ("tomato", "common", "round"), ("lettuce", "common", "low"),
    ("sunflower", "common", "tall"), ("morningglory", "common", "round"),
    ("rose", "uncommon", "round"), ("tulip", "uncommon", "tall"),
    ("lavender", "uncommon", "tall"), ("monstera", "uncommon", "low"),
    ("bamboo", "rare", "tall"), ("maple", "rare", "round"),
    ("cherry", "rare", "round"), ("cactus", "rare", "low"),
    ("worldtree", "legendary", "tall"), ("rainbow", "legendary", "round"),
]
SHINY_DEN, SHINY_DEN_CHARM = 128, 32


def pick_species(roll, guarantee=None):
    pool = [c for c in CATALOG if RANK[c[1]] >= RANK[guarantee]] if guarantee else list(CATALOG)
    if not pool: pool = list(CATALOG)
    total = sum(WEIGHT[c[1]] for c in pool)
    cursor = roll % max(1, total)
    for c in pool:
        cursor -= WEIGHT[c[1]]
        if cursor < 0: return c
    return pool[-1]


def rolls_shiny(roll, charm): return roll % (SHINY_DEN_CHARM if charm else SHINY_DEN) == 0


GARDEN_TIERS = [("sill", 0), ("balc", 1), ("bed", 3), ("yard", 6),
                ("green", 10), ("arbor", 18), ("forest", 30)]


def tier_for(n):
    found = GARDEN_TIERS[0]
    for t in GARDEN_TIERS:
        if n >= t[1]: found = t
    return found


def tier_next(n):
    for t in GARDEN_TIERS:
        if t[1] > n: return t
    return None


# ── State ───────────────────────────────────────────────────────
@dataclass
class Pot:
    species: str
    water: int = 0
    stage: int = 0
    shiny: bool = False
    planted: str = "1970-01-01"
    fruit: bool = False
    cycle: int = LEGACY_CYCLE_WATER
    nutrient_uses: int = 0        # 그루에 기록한다 — 이식하면 저절로 풀린다

    @property
    def ready(self): return self.stage >= STAGE_COUNT - 1 and self.water >= self.cycle


@dataclass
class Save:
    raw_since: int = 0
    water_since: int = 0
    claimed: dict = None            # None = 아직 seed 안 됨
    last_date: str = ""
    pot: Pot = None
    pot2: Pot = None
    pending_guarantee: str = None
    garden: list = field(default_factory=list)
    inv: dict = field(default_factory=dict)
    passives: list = field(default_factory=list)
    decorations: list = field(default_factory=list)
    last_water_day: str = ""
    water_use_day: str = ""
    water_uses_today: int = 0
    streak: int = 0
    last_decay_day: str = ""
    fert_until: str = None          # 날짜 키로 단순화
    tonic_until: str = None
    events: list = field(default_factory=list)
    baseline_set: bool = False
    raw_wallet: int = 0
    # 지갑이 **늘어난 곳과 줄어든 곳에서** 각각 센다. 파생식으로 만들면
    # 첫날 상한에 걸려 버린 분이 영원히 "쓴 것"으로 찍힌다.
    raw_earned: int = 0
    raw_spent: int = 0
    daily_raw: dict = field(default_factory=dict)
    # 환산비율을 실측하려면 **분모**도 날짜별로 있어야 한다 — 원시만 쌓아두면 못 나눈다.
    daily_water: dict = field(default_factory=dict)
    history_backfilled: bool = False
    last_use_day: str = ""
    window_tier: dict = field(default_factory=dict)
    windows_seeded: bool = False

    def count(self, item): return self.inv.get(item, 0)
    @property
    def has_charm(self): return "shinyCharm" in self.passives
    @property
    def has_slot(self): return "potSlot" in self.passives

    def fert_active(self, today):
        return self.fert_until is not None and self.fert_until > today


def dk(d): return d.isoformat()
def dparse(s): return date.fromisoformat(s)
def ddays(a, b):
    if not a or not b: return 0
    return (dparse(b) - dparse(a)).days


COALESCE = dict(levelUp="levelUp", fruit="fruit", ready="ready", transplant="transplant",
                wilt="wilt", leafFall="leafFall", newSeed="newSeed")


def push(s, kind, payload=None):
    s.events = [e for e in s.events if e[0] != kind]
    s.events.append((kind, payload))
    if len(s.events) > 8: s.events = s.events[-8:]


def drain(s):
    e = s.events
    s.events = []
    return e


def bump_streak(s, today):
    """스트릭은 **토큰을 쓴 날**을 센다 — 부은 날이 아니다."""
    if s.last_use_day == today: return
    if not s.last_use_day:
        s.streak = 1
    elif ddays(s.last_use_day, today) == 1:
        s.streak += 1
    else:
        s.streak = 1
    s.last_use_day = today


def grow(s, which, ml):
    pot = getattr(s, which)
    if pot is None: return
    was_ready = pot.ready
    pot.water += ml
    guard = 0
    while guard < STAGE_COUNT + 2:
        guard += 1
        target = stage_index(pot.water, pot.cycle)
        if target <= pot.stage: break
        pot.stage += 1
        push(s, "levelUp", pot.stage)
        if pot.stage == 8 and not pot.fruit:
            pot.fruit = True
            push(s, "fruit")
    if pot.ready and not was_ready:
        push(s, "ready")


def ingest(s, today_by_provider, today):
    if s.claimed is None:
        s.claimed = dict(today_by_provider)
        s.last_date = today
        s.baseline_set = True
        snap = TD()
        for v in today_by_provider.values(): snap = snap + v
        snap = snap.clamped()
        s.raw_since += snap.raw
        # 첫날은 두 물길 모두 상한까지만 — 안 그러면 설치 전 로그가 소급된다.
        cycle = s.pot.cycle if s.pot else cycle_water(ASSUMED_DAILY_RAW)
        credit(s, min(first_day_raw_cap(ASSUMED_DAILY_RAW), snap.raw),
               min(first_day_credit(cycle), water_from(snap)), today)
        return
    baseline = s.claimed
    if s.last_date != today:
        s.last_date = today
        baseline = {}
    total = TD()
    nxt = dict(baseline)
    for pid, snap in today_by_provider.items():
        prev = baseline.get(pid, TD())
        delta = (snap - prev).clamped()
        if not delta.is_zero: total = total + delta
        nxt[pid] = snap
    s.claimed = nxt
    s.raw_since += total.raw
    credit(s, total.raw, water_from(total), today)


def credit(s, raw, ml, today):
    """쓴 토큰이 두 곳으로 간다: 지갑(원시)과 화분(가중 환산 mL).

    둘은 서로 뺏지 않는다. 상점에서 써도 이미 자란 건 그대로다.
    """
    if raw <= 0 and ml <= 0: return
    bump_streak(s, today)

    s.raw_wallet += raw
    s.raw_earned += raw
    s.daily_raw[today] = s.daily_raw.get(today, 0) + raw
    s.daily_raw = pruned_daily(s.daily_raw, today)
    if ml > 0:
        # 보너스를 **먹이기 전** 값을 쌓는다. 스트릭·거름이 섞이면 환산비율이 아니라
        # "요즘 보너스가 얼마나 붙었나"를 재게 된다.
        s.daily_water[today] = s.daily_water.get(today, 0) + ml
        s.daily_water = pruned_daily(s.daily_water, today)

    apply_water(s, ml, today)
    # mL 이 0으로 내림돼도 토큰을 쓴 건 사실이다 — 안 찍으면 매일 쓰는 사람이 말라 죽는다.
    if raw > 0 and s.last_water_day != today:
        s.last_water_day = today


def pruned_daily(daily, today):
    """시계가 앞으로 튀면 한 번의 정리로 기록 전체가 날아간다 — 그 `today` 는 안 믿는다."""
    if daily and ddays(max(daily), today) > DAILY_WINDOW * 2:
        return daily
    return {k: v for k, v in daily.items() if ddays(k, today) < DAILY_WINDOW}


def daily_rate(daily):
    # 최근 창의 달력일 평균. 안 쓴 날도 0으로 센다 — 실제로 쌓이는 속도가 그거다.
    if not daily:
        return ASSUMED_DAILY_RAW
    keys = sorted(daily)
    span = ddays(keys[0], keys[-1]) + 1
    if span < DAILY_MIN_DAYS:
        return ASSUMED_DAILY_RAW
    return max(1, sum(daily.values()) // span)


def baseline_raw_rate(daily, today):
    """**오늘을 뺀** 평균. 기준에 오늘이 있으면 오늘이 끌어내린 평균과 오늘을 견주게 된다."""
    past = {k: v for k, v in daily.items() if k != today}
    keys = sorted(past)
    if not keys: return None
    span = ddays(keys[0], keys[-1]) + 1
    if span < DAILY_MIN_DAYS: return None
    return max(1, sum(past.values()) // span)


def measured_raw_per_ml(raw, water):
    """원시 토큰 몇 개가 1mL 인가 — 상수 대신 각자 재는 값."""
    keys = set(raw) & set(water)
    if len(keys) < DAILY_MIN_DAYS: return None
    r = sum(raw[k] for k in keys)
    w = sum(water[k] for k in keys)
    if w <= 0 or r <= 0: return None
    return max(1, r // w)


def backfill_history(s, by_day, today):
    """설치 직후 한 번 — 과거 로그로 통계만 채운다. **지갑·성장은 안 건드린다.**"""
    if s.history_backfilled: return False
    for day, delta in by_day.items():
        if day == today: continue      # ingest 가 오늘을 적립한다 — 넣으면 두 번 세어진다
        c = delta.clamped()
        s.daily_raw[day] = s.daily_raw.get(day, 0) + c.raw
        ml = water_from(c)
        if ml > 0: s.daily_water[day] = s.daily_water.get(day, 0) + ml
    s.daily_raw = pruned_daily(s.daily_raw, today)
    s.daily_water = pruned_daily(s.daily_water, today)
    s.history_backfilled = True
    return True


def measured_daily_water(water, today):
    """하루에 실제로 들어간 mL — 상수 환산이 아니라 기록에서 읽는다."""
    past = {k: v for k, v in water.items() if k != today}
    keys = sorted(past)
    if not keys: return None
    span = ddays(keys[0], keys[-1]) + 1
    if span < DAILY_MIN_DAYS: return None
    return max(1, sum(past.values()) // span)


def days_to_transplant(s, today):
    """화면의 "이식까지 약 N일". 분모가 상수 환산이면 3배까지 거짓말이 된다."""
    if s.pot is None: return None
    remaining = max(0, s.pot.cycle - s.pot.water)
    if remaining <= 0: return 0
    base = measured_daily_water(s.daily_water, today) or max(1, daily_rate(s.daily_raw) // RAW_PER_ML)
    per_day = applied(base, s.streak, s.fert_active(today))
    return -(-remaining // max(1, per_day))     # 올림


def days_for(raw, rate):
    return raw / max(1, rate)


def apply_water(s, ml, today):
    """물을 모든 화분에 먹인다. 자동 성장과 아이템이 같이 쓰는 길이다.

    보너스는 여기서 한 번만 곱한다 — 경로마다 규칙이 갈리면 아무도 못 맞춘다.
    """
    if ml <= 0: return 0
    got = applied(ml, s.streak, s.fert_active(today))
    s.water_since += got
    s.last_water_day = today
    grow(s, "pot", got)
    if s.pot2 is not None:
        grow(s, "pot2", got)
    return got


def evaluate_window_grants(windows, tier):
    """엣지 트리거 — 100% 를 새로 넘어선 순간만. 아래로 내려가면 재무장."""
    grants = []
    for key, kind, util in windows:
        if util < 100:
            tier.pop(key, None)
            continue
        if tier.get(key, 0) >= 1: continue
        tier[key] = 1
        grants.append((key, WINDOW_SESSION if kind == "session" else WINDOW_WEEKLY))
    return grants


def grant_window_bonus(s, windows, is_ready):
    if not is_ready: return 0
    if not s.windows_seeded:
        # 첫 실행: 이미 100% 인 창은 지급 없이 시드만 — 소급 지급 차단.
        for key, _kind, util in windows:
            if util >= 100: s.window_tier[key] = 1
        s.windows_seeded = True
        return 0
    total = 0
    for key, amount in evaluate_window_grants(windows, s.window_tier):
        # 성장에도 스트릭에도 하루 유입 통계에도 안 섞인다. 지갑과 누적에만 얹는다 —
        # 화면이 "번 것 − 쓴 것 = 지갑"을 그대로 보여주므로 누적을 빼면 뺄셈이 안 맞는다.
        s.raw_wallet += amount
        s.raw_earned += amount
        s.raw_since += amount
        total += amount
        push(s, "window", (key, amount))
    return total


def thirst_level(s, today):
    """누적 물은 안 깎는다 — 색만 마른다.

    잔액 모델에서 물을 안 주면 안 자라는 것 자체가 이미 결과다.
    거기에 진행도까지 깎으면 실제로 쓴 토큰을 두 번 벌주는 셈이라 감쇠를 통째로 뺐다.
    """
    if not s.last_water_day: return 0.0
    idle = ddays(s.last_water_day, today)
    if idle < THIRSTY_AFTER: return 0.0
    if idle >= PARCHED_AFTER: return 1.0
    span = float(PARCHED_AFTER - THIRSTY_AFTER)
    return min(1.0, (idle - THIRSTY_AFTER) / max(1.0, span))


def price(s, item):
    return price_for(item, daily_rate(s.daily_raw))


def can_buy(s, item):
    if item in PASSIVE and item in s.passives: return ("alreadyOwned", 0)
    short = price(s, item) - s.raw_wallet
    return ("insufficient", short) if short > 0 else ("ok", 0)


def next_goal(s):
    """아직 못 사는 품목 중 제일 싼 것. **장식은 뺀다** —
    벤치가 1일치라 늘 먼저 걸리는데 성장에 아무 도움이 안 된다."""
    for item in sorted(PRICE_DAYS, key=lambda k: PRICE_DAYS[k]):
        # 장식 뽑기도 뺀다 — 정원에 놓이는 물건은 아니지만 성장에 도움이 안 되는 건 같다.
        if item in DECORATION or item == "decorBox": continue
        kind, short = can_buy(s, item)
        if kind == "insufficient": return (item, short)
    return None


def earned_total(s): return s.raw_earned
def spent_total(s): return s.raw_spent


def buy(s, item):
    r = can_buy(s, item)
    if r[0] != "ok": return r
    cost = price(s, item)
    s.raw_wallet -= cost
    s.raw_spent += cost
    if item in PASSIVE:
        s.passives.append(item)
        # 장식은 가방에 담을 이유가 없다 — 살 때 정원에 바로 놓인다.
        if item in DECORATION:
            s.decorations.append(item)
        if item == "potSlot" and s.pot2 is None and s.pot is not None:
            # 목표를 안 넘기면 기본값(legacy 400,000)이 박혀서 둘째 화분만 남의 값을 받는다.
            s.pot2 = Pot(species=s.pot.species, cycle=seed_cycle(s))
    else:
        s.inv[item] = s.count(item) + 1
    return ("ok", 0)


def consume(s, item):
    n = s.count(item)
    if n <= 1: s.inv.pop(item, None)
    else: s.inv[item] = n - 1


def use(s, item, today, roll=0):
    if s.count(item) <= 0: return ("notOwned", 0)
    if item == "decorBox":
        # **아직 없는 것 중에서만** 뽑는다 — 중복이 나오면 "돈 냈는데 꽝"이 생긴다.
        owned = set(s.decorations)
        pool = [k for k in GACHA_DECOR if k not in owned]
        if not pool: return ("noEffect", 0)
        consume(s, item)
        picked = pool[roll % len(pool)]
        s.decorations.append(picked)
        push(s, "decor", picked)
        return ("ok", 0)
    if s.pot is None: return ("notOwned", 0)
    if item == "water":
        # 하루 상한. **소모 전에** 막는다 — 먼저 consume 하면 산 물이 그냥 사라진다.
        if s.water_use_day != today:
            s.water_use_day = today
            s.water_uses_today = 0
        if s.water_uses_today >= DAILY_WATER_USES:
            return ("noEffect", 0)
        s.water_uses_today += 1
        # 정액. 자동 성장과 같은 길로 들어가 보너스도 똑같이 받는다.
        consume(s, item)
        return ("ok", apply_water(s, water_ml(daily_rate(s.daily_raw)), today))
    if item == "fertilizer":
        # **남은 기간에 이어 붙인다.** 배수는 안 겹치고 기간만 는다 —
        # 예전엔 7일이 다시 시작이라 돌고 있는 동안 쓰면 남은 날이 날아갔고,
        # 그래서 화면이 버튼을 막아 "사도 바로 못 쓰는 품목"이 됐다.
        base = max(today, s.fert_until or today)
        ceiling = dk(dparse(today) + timedelta(days=FERT_MAX_DAYS))
        if base >= ceiling: return ("noEffect", 0)
        consume(s, item)
        s.fert_until = min(dk(dparse(base) + timedelta(days=FERT_DAYS)), ceiling)
        return ("ok", 0)
    if item == "nutrient":
        # 한 그루에 한 번. 날짜로 세면 "하루 지나면 또"가 되어 한 그루에 열 개도 들어간다.
        if s.pot.nutrient_uses >= NUTRIENT_PER_PLANT:
            return ("noEffect", 0)
        g = nutrient_gain(s.pot.water, s.pot.cycle)
        if g <= 0: return ("noEffect", 0)
        consume(s, item)
        s.pot.nutrient_uses += 1
        # **이 그루에만** — apply_water 를 타면 화분 2에도 공짜로 들어가서
        # "한 그루에 한 번"이 거짓이 되고, 양도 화분 1 기준으로 매겨진다.
        got = applied(g, s.streak, s.fert_active(today))
        s.water_since += got
        s.last_water_day = today
        grow(s, "pot", got)
        return ("ok", got)
    if item in SEED_GUARANTEE:
        # 예약 칸은 하나뿐이다. 덮어쓰면 전설 위에 고급을 올려 **등급이 내려가고**
        # 산 전설이 그대로 사라진다. 같거나 낮은 등급은 소모 전에 거절한다.
        nxt = SEED_GUARANTEE[item]
        if s.pending_guarantee and RANK[s.pending_guarantee] >= RANK[nxt]:
            return ("noEffect", 0)
        consume(s, item)
        s.pending_guarantee = nxt
        return ("ok", 0)
    return ("noEffect", 0)


def plant_new_seed(s, roll, today="2026-09-01", slot=0):
    key = "pot" if slot == 0 else "pot2"
    # 보증은 첫 화분에만 소비한다 — 두 슬롯이 동시에 완주해도 산 것을 두 번 받으면 안 된다.
    g = s.pending_guarantee if slot == 0 else None
    if slot == 0: s.pending_guarantee = None
    sp = pick_species(roll, g)
    shiny = rolls_shiny(roll >> 10, s.has_charm)
    setattr(s, key, Pot(species=sp[0], shiny=shiny, planted=today, cycle=seed_cycle(s)))
    push(s, "newSeed", (sp[0], sp[1], shiny))


def transplant(s, roll, today="2026-09-01", slot=0):
    key = "pot" if slot == 0 else "pot2"
    pot = getattr(s, key)
    if pot is None or not pot.ready: return False
    # 상한 없음 — 꽉 차서 막으면 화분이 완주 상태로 영원히 대기하고 게임이 멈춘다.
    s.garden.append(dict(species=pot.species, shiny=pot.shiny,
                         planted=pot.planted, total=pot.water))
    push(s, "transplant", (pot.species, pot.shiny))
    setattr(s, key, None)
    plant_new_seed(s, roll, today, slot)
    return True
