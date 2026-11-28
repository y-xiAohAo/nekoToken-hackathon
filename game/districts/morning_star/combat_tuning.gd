extends RefCounted

const BOSS_HEALTH := 140
const PLAYER_HEALTH := 5
const PUNCHES_PER_OPENING := 2
const INTRO_TIME := 0.86
const DEFEAT_TIME := 2.5

# Player action times, in seconds. Physics is authoritative for these windows.
const INPUT_BUFFER := 0.15
const PUNCH_HIT_START := 0.100
const PUNCH_HIT_END := 0.167
const PUNCH_DODGE_CANCEL := 0.167
const PUNCH_MOVE_CANCEL := 0.215
const PUNCH_CHAIN := 0.235
const PUNCH_DURATION := 0.315
const PUNCH_LUNGE_SPEED := 2.8
const PUNCH_REACH := 2.05
const PUNCH_ARC_DOT := 0.44
const PUNCH_DAMAGE := 20
const DODGE_DURATION := 0.265
const DODGE_RECOVER := 0.195
const DODGE_INVUL := 0.150
const DODGE_COOLDOWN := 0.54
const DODGE_SPEED := 10.8
const HURT_STAGGER := 0.115
const HURT_GRACE := 0.54
const HURT_PUSH := 3.8
const HURT_FLASH := 0.24

# Per-event feedback limits. Stop time is encounter-local, not global time scale.
const HIT_STOP := 2.0 / 60.0
const GUARD_STOP := 1.0 / 60.0
const BREAK_STOP := 4.0 / 60.0
const HURT_STOP := 3.0 / 60.0
const HIT_SHAKE := 0.075
const GUARD_SHAKE := 0.033
const BREAK_SHAKE := 0.19
const HURT_SHAKE := 0.14
const SHAKE_DURATION := 0.19
const MAX_SHAKE := 0.21

# Attack envelopes in WALL / DASH / PREDICT / PULSE order.
enum Move { WALL, DASH, PREDICT, PULSE }

const WINDUP: Array[float] = [1.16, 0.95, 0.84, 0.78]
const STRIKE: Array[float] = [0.60, 0.48, 0.29, 0.46]
const SKILL_COOLDOWN: Array[float] = [4.4, 4.2, 4.7, 3.7]
const WALL_ANGLE := deg_to_rad(47.0)
const WALL_SAFE := 1.9
const WALL_DEPTH := 2.75
const DASH_WIDTH := 1.02
const DASH_MIN_LENGTH := 7.0
const DASH_OVERSHOOT := 2.1
const DASH_WALL_MARGIN := 1.0
const PREDICT_RADIUS := 1.45
const PREDICT_LEAD := 0.52
const PULSE_RADIUS := 3.72
const PULSE_THICKNESS := 0.83
const TIER_TWO_HP := 100
const TIER_THREE_HP := 60
const PHASE_TRANSITION := 0.83
const REPOSITION_TIME := 0.54
const COMBO_BREATH := 0.31
const ECHO_WINDUP := 0.72
const SIGNATURE_COOLDOWN := 9.8
const RECOVERY_MIN := 2.36
const RECOVERY_MAX := 3.30
const STREAK_PUNISH_ROOM := 1.20
const ORBIT_RADIUS := 3.15
const TELEGRAPH_TINTS: Array[Color] = [
	Color("#78eaff"), Color("#aafaff"), Color("#8db8ff"), Color("#c4b6ff"),
]
const STAGE_TINTS: Array[Color] = [Color("#63e2ed"), Color("#86aaff"), Color("#b3a0ff")]
