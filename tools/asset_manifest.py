#!/usr/bin/env python3
"""美术资源总清单（依据《场景图片需求表》《角色立绘表情表》）

这份清单是「待生成资源」的唯一事实来源：
  * 记录每张图的 id / 文件名 / 优先级 / 用途
  * 附带可直接投喂给 AI 生图的英文提示词
  * check_assets.py 与 gen_prompts.py 都从这里取数据

统一画风关键词（用户指定）：
  日系悬疑校园AVG风、干净线稿、低饱和冷色调、细致校服褶皱、轻阴影、
  统一站姿立绘、透明背景、全身完整、双脚完整入镜
"""

# ============================================================ 通用画风
STYLE_SPRITE = (
    "clean lineart, Japanese suspense school AVG illustration style, "
    "low saturation cold color palette, detailed uniform fabric folds, "
    "soft flat shading, unified standing pose. "
    "FULL BODY from head to feet, both feet fully visible in frame. "
    "Tall vertical portrait composition, character centered, "
    "filling nearly the entire image height. "
    "PURE FLAT WHITE BACKGROUND, exactly ONE character, no scenery, "
    "no room, no wall, no floor, no cast shadow."
)
NEG_SPRITE = (
    "Negative: no background scenery, no environment, no half body, no cropping, "
    "no second character, no duplicate, no ghost copy, no mirror image, "
    "no exaggerated pose, no weapons, no oversexualization, no chibi, "
    "no cartoon proportions, no extra limbs, no stage lighting."
)
STYLE_BG = (
    "Background art for a Chinese school horror visual novel, NO PEOPLE, empty scene. "
    "Japanese suspense visual novel background art, semi-realistic detailed painted "
    "illustration, low saturation cold color palette, heavy shadows, oppressive "
    "atmosphere, subtle film grain. Wide 16:9 horizontal composition. "
    "No characters, no text overlay, no watermark."
)

# ============================================================ 角色基础设定
CHAR_BASE = {
    "zhouxu": "One 17-year-old Chinese high school boy, class monitor. Very short tidy "
              "black hair, clean forehead. Blue-and-white Chinese school tracksuit uniform "
              "worn neatly, zipped up, collar straight. Slightly tall lean build, "
              "faint dark circles under eyes.",
    "liangye": "One 17-year-old Chinese high school boy. Messy overgrown black hair "
               "sticking up. Blue-and-white Chinese school tracksuit uniform worn untidily, "
               "jacket unzipped over a white shirt, collar crooked. Thin restless build.",
    "xuqing": "One young Chinese female high school teacher, late 20s. Long straight black "
              "hair tied low over one shoulder. Dark navy high-neck top under a black "
              "cardigan, long dark grey skirt. BAREFOOT, no shoes, bare feet clearly "
              "visible and fully in frame.",
    "shenhe": "One 17-year-old Chinese high school girl, ghostly presence. Long black hair, "
              "slightly DAMP and clinging, wet strands over her face. OLD-STYLE outdated "
              "Chinese school uniform, sleeve cuffs and hem show damp water stains and faint "
              "charred blackened scorch marks. Pale skin.",
    "oldqin": "One Chinese man in his late 50s, school night-shift security guard. Short "
              "greying buzzcut, thinning on top, weathered lined face. Worn dark blue "
              "security guard uniform jacket, rumpled. Stocky build, slight stoop.",
    "linday": "One 17-year-old Chinese high school boy, transfer student. Short black hair "
              "with slightly overgrown fringe. Blue-and-white Chinese school tracksuit "
              "uniform. Thin build, pale, low presence.",
}

POSE_DESC = {
    ("zhouxu", "pose01"): "Standing straight, shoulders level, restrained and guarded, "
                          "as if ready to stop you at any moment.",
    ("zhouxu", "pose02"): "Leaning slightly, arms folded, stronger scrutinizing pressure.",
    ("liangye", "pose01"): "Loose casual standing, ordinary schoolboy energy.",
    ("liangye", "pose02"): "Shoulders hunched and tense, visibly frightened but "
                           "still talking tough.",
    ("liangye", "pose03"): "Off-balance stance, weight wrong, as if about to be "
                           "dragged away by something.",
    ("liangye", "pose04"): "Half-assimilated: vacant eyes, delayed sluggish body language, "
                           "standing unnaturally still and straight.",
    ("xuqing", "pose01"): "Standing perfectly upright holding a clipboard with a name "
                          "roster, front-facing, taking attendance.",
    ("xuqing", "pose02"): "Standing quietly at a doorway, turned slightly to the side, "
                          "as if she had been there all along.",
    ("xuqing", "pose03"): "Head lowered, looking down at the roster or a file in her hands.",
    ("shenhe", "pose01"): "Standing still and quiet, arms hanging naturally, like a student "
                          "called out of class.",
    ("shenhe", "pose02"): "Head tilted slightly down, tired, damp, uncomfortably familiar.",
    ("shenhe", "pose03"): "Leaning very slightly forward, as if asking your name "
                          "or drawing closer.",
    ("shenhe", "pose04"): "Standing as if just rising from the broadcaster's chair.",
    ("oldqin", "pose01"): "Stooped standing posture, a man who has guarded the old "
                          "building far too long, holding an enamel tea mug.",
    ("oldqin", "pose02"): "Glancing nervously to the side, as if afraid of being overheard.",
    ("linday", "pose01"): "Standing straight, arms relaxed at sides, quiet and observant.",
    ("linday", "pose02"): "Stopped in a doorway, frozen at the moment his name is called.",
    ("linday", "pose03"): "Sitting in / standing before the broadcaster's chair, "
                          "emptied out.",
}

EXP_DESC = {
    "neutral": "calm composed neutral expression, eyes looking at viewer",
    "normal": "ordinary relaxed everyday expression",
    "calm": "quiet calm expression, deeply tired underneath, resigned, not angry",
    "frown": "frowning, sensing something is wrong, wary",
    "serious": "serious expression, about to state something important",
    "tired": "exhausted expression, heavy eyelids, worn down",
    "urgent": "urgent pressing expression, trying to stop or hurry you",
    "dark": "grim shadowed expression, cold and coercive",
    "soft": "slightly softened expression, guard partly lowered",
    "annoyed": "irritated sulky expression, talking back",
    "nervous": "nervous expression, false bravado covering fear",
    "scared": "openly frightened expression, wide eyes",
    "blank": "vacant hollow expression, mind emptied out",
    "relief": "relieved expression, tension just released",
    "fragile": "fragile weak smile, a flicker of returning humanity",
    "half": "half-assimilated: empty unfocused eyes, face slack, wrong stillness",
    "stare": "staring directly and unblinkingly at the viewer, oppressive",
    "displeased": "displeased expression, a rule has been broken",
    "faintsmile": "very faint unsettling smile that does not reach the eyes",
    "empty": "empty expression, does not look like a living person",
    "unstable": "destabilized expression, composure cracking",
    "sad": "sorrowful expression, quiet grief",
    "hurt": "wounded pained expression, remembering the fire",
    "hollow": "hollow void expression, presence draining away",
    "release": "expression of release and letting go, finally free, faint peace",
    "warning": "warning expression, urging you not to go",
    "shocked": "shocked expression, caught off guard",
    "confused": "confused bewildered expression",
    "determined": "determined resolute expression",
}

# ============================================================ 立绘清单
# (char_id, pose, exp, priority)  priority: S=必做 A=重要 B=可选
SPRITES = [
    # —— 周叙 12
    ("zhouxu", "pose01", "neutral", "S"), ("zhouxu", "pose01", "frown", "S"),
    ("zhouxu", "pose01", "serious", "S"), ("zhouxu", "pose01", "tired", "A"),
    ("zhouxu", "pose01", "urgent", "A"), ("zhouxu", "pose01", "soft", "B"),
    ("zhouxu", "pose02", "neutral", "A"), ("zhouxu", "pose02", "frown", "A"),
    ("zhouxu", "pose02", "serious", "A"), ("zhouxu", "pose02", "tired", "B"),
    ("zhouxu", "pose02", "urgent", "A"), ("zhouxu", "pose02", "dark", "B"),
    # —— 梁野 14
    ("liangye", "pose01", "normal", "S"), ("liangye", "pose01", "annoyed", "A"),
    ("liangye", "pose01", "nervous", "A"), ("liangye", "pose02", "nervous", "S"),
    ("liangye", "pose02", "scared", "S"), ("liangye", "pose02", "relief", "A"),
    ("liangye", "pose02", "fragile", "B"), ("liangye", "pose03", "blank", "A"),
    ("liangye", "pose03", "scared", "A"), ("liangye", "pose03", "relief", "B"),
    ("liangye", "pose03", "fragile", "B"), ("liangye", "pose04", "half", "A"),
    ("liangye", "pose04", "blank", "B"), ("liangye", "pose04", "scared", "B"),
    # —— 许清 12
    ("xuqing", "pose01", "neutral", "S"), ("xuqing", "pose01", "stare", "S"),
    ("xuqing", "pose01", "displeased", "A"), ("xuqing", "pose01", "faintsmile", "A"),
    ("xuqing", "pose02", "neutral", "A"), ("xuqing", "pose02", "stare", "A"),
    ("xuqing", "pose02", "empty", "A"), ("xuqing", "pose02", "faintsmile", "B"),
    ("xuqing", "pose03", "neutral", "B"), ("xuqing", "pose03", "empty", "A"),
    ("xuqing", "pose03", "unstable", "B"), ("xuqing", "pose03", "displeased", "B"),
    # —— 沈禾 12
    ("shenhe", "pose01", "calm", "S"), ("shenhe", "pose01", "tired", "A"),
    ("shenhe", "pose01", "hurt", "A"), ("shenhe", "pose02", "calm", "A"),
    ("shenhe", "pose02", "tired", "A"), ("shenhe", "pose02", "sad", "A"),
    ("shenhe", "pose02", "faintsmile", "A"), ("shenhe", "pose03", "hurt", "B"),
    ("shenhe", "pose03", "hollow", "B"), ("shenhe", "pose03", "faintsmile", "B"),
    ("shenhe", "pose04", "calm", "B"), ("shenhe", "pose04", "release", "S"),
    # —— 老秦 4
    ("oldqin", "pose01", "normal", "A"), ("oldqin", "pose01", "warning", "A"),
    ("oldqin", "pose02", "nervous", "B"), ("oldqin", "pose02", "shocked", "B"),
    # —— 林昼 6
    ("linday", "pose01", "neutral", "B"), ("linday", "pose01", "confused", "B"),
    ("linday", "pose02", "shocked", "B"), ("linday", "pose02", "determined", "B"),
    ("linday", "pose03", "empty", "A"), ("linday", "pose03", "neutral", "B"),
]

# ============================================================ 场景清单
# (file_name, priority, scene description)
BACKGROUNDS = [
    ("office_day", "A",
     "A Chinese school teachers' office in daytime. Rows of desks with stacked exam papers, "
     "metal filing cabinets, a thermos, an old desktop computer. Afternoon light through "
     "dusty blinds, still and airless. A crumpled disciplinary record form on one desk."),
    ("classroom_day", "A",
     "A Chinese high school classroom in daytime, 45-degree angle view. Neat rows of worn "
     "wooden desks, green chalkboard, ceiling fans, windows with daylight. Ordinary and "
     "mundane, but slightly too quiet. One back-row seat by the window is empty."),
    ("classroom_evening", "S",
     "A Chinese high school classroom at night during evening self-study. Rows of worn desks "
     "with textbooks. Green chalkboard with faint unerased writing. Windows turned into black "
     "mirrors by the darkness outside. One flickering fluorescent tube. The back row seat by "
     "the window is conspicuously EMPTY with old textbooks still stacked on it."),
    ("hallway_day", "B",
     "A Chinese school building corridor in daytime, long one-point perspective. Windows "
     "along one side, notice boards with peeling paper, classroom doors receding into "
     "distance, worn terrazzo floor."),
    ("hallway_night", "A",
     "A Chinese school building corridor at night, long one-point perspective, completely "
     "empty. Most ceiling lights off, one flickering. Classroom doors dark. Deep shadows "
     "swallowing the far end of the corridor. Oppressive emptiness."),
    ("library_day", "A",
     "An old Chinese school library, tall wooden bookshelves, worn reading tables, dust "
     "floating in shafts of window light. Card catalog drawers. Slightly abandoned feeling."),
    ("library_dim", "B",
     "An old Chinese school library in dim light, tall shelves receding into darkness, "
     "corners unnaturally black, a single desk lamp. Dust, silence, wrongness."),
    ("dorm_307_day", "B",
     "A Chinese student dormitory room in daytime, four metal bunk beds, mosquito nets, "
     "cluttered desks, washbasins, clothes hanging. Cramped and lived-in, worn but ordinary."),
    ("dorm_307_night", "S",
     "A Chinese student dormitory room at night, lights out. Four metal bunk beds with "
     "mosquito nets hanging like shrouds. The door is closed, a thin line of corridor light "
     "glowing underneath it. Moonlight through a barred window. Suffocating darkness."),
    ("dorm_corridor_night", "A",
     "A Chinese dormitory corridor at night, long perspective, doors with room number plates "
     "on both sides, a single flickering fluorescent tube, wet patches on the concrete floor, "
     "deep darkness at the far end."),
    ("duty_room", "B",
     "A small cramped school security duty room. Old desk, a key board on the wall with many "
     "hooks and three empty, a tiny CRT television showing static, enamel tea mug, ashtray "
     "full of cigarette butts, walls yellowed by smoke."),
    ("old_building_gate_rain", "A",
     "The entrance of an abandoned school building at night in heavy rain. Rusted iron gate "
     "and chain-link fence with a torn gap. Windows boarded with wooden planks. ONE window on "
     "the third floor is faintly lit. Overgrown weeds, puddles reflecting the single light."),
    ("old_building_stairs", "A",
     "A dark stairwell inside an abandoned school building. Concrete steps with peeling paint, "
     "rusted handrail, floor number sign, upward perspective into blackness. Blistered "
     "plaster bulging off the walls like waterlogged paper. Thick dust with footprints "
     "going only upward."),
    ("old_building_corridor", "S",
     "A corridor inside an abandoned school building. Peeling swollen wall plaster, thick "
     "dust, debris. A red indicator light glowing from a half-open iron door at the far end, "
     "casting long shadows down the corridor. Extremely oppressive."),
    ("broadcast_door", "S",
     "A heavy rusted iron door of a school broadcast room, viewed head-on. The door is ajar, "
     "a red light pulsing through the gap. A faded door sign. Rust streaks, water stains, "
     "scorch marks along the bottom edge. Darkness all around."),
    ("broadcast_room", "S",
     "An abandoned school broadcast room, derelict for five years. Old analog mixing console, "
     "dusty faders, red indicator lights still glowing. A vintage microphone on a boom arm. "
     "Peeling grey soundproofing foam, several panels fallen revealing CHARRED blackened wood. "
     "An empty broadcaster's chair. Scattered yellowed name lists on the floor."),
    ("school_history_hall", "A",
     "A Chinese school history exhibition hall, dim. Glass display cases with trophies and "
     "medals, a wall of framed graduation class photos spanning years, red banners. One photo "
     "frame has a conspicuous empty gap where a student should be standing."),
    ("archive_inner_door", "B",
     "A hidden iron door behind a false wall, viewed head-on. Half sealed with concrete, an "
     "old door plate still readable, a rusted keyhole. Dust and cobwebs. Something kept shut "
     "for years."),
    ("monitor_room", "S",
     "A cramped monitoring and archive room. A wall of stacked old CRT monitors glowing sickly "
     "green, some showing corridor feeds, some pure static. A running VCR with a red recording "
     "light. Metal archive shelves packed with files. Tangled cables hanging down."),
    ("campus_rain", "B",
     "A Chinese school campus at night in the rain, wide view. Empty sports field, running "
     "track, a flagpole, teaching buildings with a few lit windows, street lamps with halos "
     "in the rain, puddles on the ground reflecting light."),
    ("void_broadcast_edge", "A",
     "An abstract non-real space: the boundary of a broadcast void. Floating fragments of "
     "classroom desks and name-list paper drifting in an endless dark grey emptiness. Faint "
     "radio wave ripples. Rows of empty chairs receding into nothing. Surreal, dreamlike, "
     "deeply lonely, not gory."),
    ("title_school", "B",
     "A Chinese high school seen from outside at dusk, wide establishing shot. Several "
     "teaching buildings, a sports field, the easternmost building dark and boarded up. "
     "Overcast heavy sky, humid southern Chinese atmosphere, melancholic and quiet."),
]

# ============================================================ 场景变体
VARIANTS = [
    ("classroom_evening_alllook", "classroom_evening", "S",
     "same classroom at night during evening self-study, but EVERY student in the room has "
     "turned their head to stare directly at the viewer, faces indistinct and shadowed"),
    ("classroom_evening_missingseat", "classroom_evening", "A",
     "same classroom, but one desk and chair are completely gone, leaving a conspicuous gap "
     "in the row with clean floor where they stood"),
    ("dorm_307_night_shadow", "dorm_307_night", "S",
     "same dark dormitory, close on the door: the strip of light under the door is broken by "
     "THREE distinct standing shadows, though only two feet should be there"),
    ("dorm_307_night_wetfloor", "dorm_307_night", "A",
     "same dark dormitory, with a trail of wet footprints and a spreading puddle of water "
     "leading from the door to the middle of the room"),
    ("dorm_307_night_namewall", "dorm_307_night", "A",
     "same dark dormitory, with faint handwritten Chinese-looking name characters slowly "
     "surfacing on the wall like damp stains, illegible and blurred"),
    ("old_building_corridor_red", "old_building_corridor", "S",
     "same abandoned corridor but drenched in pulsing deep red emergency light, "
     "shadows stretched long and distorted"),
    ("old_building_corridor_water", "old_building_corridor", "B",
     "same abandoned corridor with the floor flooded in shallow standing water, "
     "reflecting the ceiling in an unsettling mirror"),
    ("broadcast_door_lightline", "broadcast_door", "S",
     "same iron door, now with a bright vertical line of light spilling from the widened gap, "
     "something clearly inside"),
    ("broadcast_door_opencrack", "broadcast_door", "S",
     "same iron door now opened a hand's width, revealing only darkness and a sliver "
     "of red light within"),
    ("broadcast_room_fireedge", "broadcast_room", "S",
     "same broadcast room with the edges of the frame catching fire, papers curling and "
     "burning, orange firelight fighting the red console glow, smoke gathering at ceiling"),
    ("broadcast_room_emptyseat", "broadcast_room", "S",
     "same broadcast room focused on the empty broadcaster's chair, still slightly turned, "
     "as if someone just stood up, a faint damp mark left on the seat"),
    ("monitor_room_snow", "monitor_room", "A",
     "same monitor room but every screen has collapsed into pure white static snow, "
     "the room lit only by that flickering white noise"),
]


def sprite_filename(char_id, pose, exp):
    return f"{char_id}_{pose}_{exp}.png"


def sprite_prompt(char_id, pose, exp):
    base = CHAR_BASE[char_id]
    pd = POSE_DESC.get((char_id, pose), "Standing naturally.")
    ed = EXP_DESC.get(exp, exp)
    return f"{base} {pd} Expression: {ed}. {STYLE_SPRITE} {NEG_SPRITE}"


def bg_prompt(desc):
    return f"{STYLE_BG} Scene: {desc}"


def variant_prompt(base_desc, var_desc):
    return f"{STYLE_BG} Scene: {base_desc} VARIANT: {var_desc}"
