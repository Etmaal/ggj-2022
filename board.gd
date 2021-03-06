extends Node2D

signal action_ended(turn, result)
signal new_angle(angle)
signal rotation_started
signal rotation_complete

signal player_attacked(player, damage)

var slot_scene = preload("res://card-slots/CardSlot.tscn")
var card_db = preload("res://data/cards.tres")

export(int) var sectors = 4  # Number of card slots on each side.
export(float) var radius = 330.0
export(float, 0, 5) var rotation_duration = 2.0

var tween
var angle = 0
var player_attacking = false


func _ready():
    tween = Tween.new()
    add_child(tween)

    for sector in range(2 * sectors):
        var slot = slot_scene.instance()
        slot.get_node("Label").text = str(sector)

        $Slots.add_child(slot)
        slot.connect("slot_occupied", self, "_on_CardSlot_slot_occupied")
        slot.connect("slot_clicked", self, "_on_CardSlot_slot_clicked")

        slot.is_bottom = sector < sectors

        var angle_offset = (
            360.0 / (2 * sectors)  # Angle of a sector.
            * (sector + 0.5)  # Sector index offset + halfsector offset.
        )
        slot.position = radius * Vector2(
            cos(deg2rad(angle_offset)),
            sin(deg2rad(angle_offset)))
        slot.rotation_degrees = angle_offset + 90


func rotate_board(turns: int):
    emit_signal("rotation_started")
    var clockwise = turns > 0
    for _idx in range(abs(turns)):
        single_rotation(clockwise)
        yield(tween, "tween_all_completed")

        angle = (angle + sign(turns)) % (2 * sectors)
        emit_signal("new_angle", angle)

    for idx in range(2 * sectors):
        var is_bottom = slot_is_bottom(idx)

        # TODO: Update bottom status.
        $Slots.get_children()[idx].is_bottom = is_bottom


    emit_signal("rotation_complete")


func single_rotation(clockwise: bool):
    var angle_degrees = 360.0 / (2 * sectors)

    if not clockwise:
        angle_degrees = -angle_degrees

    tween.interpolate_property(
        self, "rotation_degrees",
        rotation_degrees, rotation_degrees + angle_degrees, rotation_duration,
        Tween.TRANS_QUINT, Tween.EASE_IN_OUT)
    tween.start()


func slot_is_bottom(slot: int) -> bool:
    return (slot + angle) % (2 * sectors) < sectors


func get_card_in_slot(idx: int):
    var slot = $Slots.get_children()[idx].get_node("Slot")

    if len(slot.get_children()) == 1:
        return slot.get_children()[0]

    return null


func player_can_place() -> bool:
    for idx in range(2 * sectors):
        if not slot_is_bottom(idx):
            continue

        var card = get_card_in_slot(idx)

        if card == null:
            return true

    return false


func player_can_attack() -> bool:
    for idx in range(2 * sectors):
        if not slot_is_bottom(idx):
            continue

        var card = get_card_in_slot(idx)

        if card == null:
            continue

        if not card.get_node("SleepParticles").isSleeping:
            return true

    return false


func opponent_can_attack() -> bool:
    for idx in range(2 * sectors):
        if slot_is_bottom(idx):
            continue

        var card = get_card_in_slot(idx)

        if card == null:
            continue

        if not card.get_node("SleepParticles").isSleeping:
            return true

    return false


func perform_opponent_attack():
    var indices = []

    for idx in range(2 * sectors):
        if slot_is_bottom(idx):
            continue

        var card = get_card_in_slot(idx)

        if card == null:
            continue

        var is_sleeping = card.get_node("SleepParticles").isSleeping
        if not is_sleeping:
            indices.append(idx)

    if len(indices) == 0:
        push_error("Could not perform attack")
        emit_signal("action_ended", "attack", {"skipped": true})
    else:
        var select = indices[randi() % len(indices)]
        var slot = $Slots.get_children()[select]

        attack(select)
        yield(slot, "slot_attacked")

        emit_signal("action_ended", "attack", {})


func attack(attacker_index: int):
    var opponent_index = (
        (attacker_index + sectors)
        % (2 * sectors))

    var attacking_card = get_card_in_slot(attacker_index)
    var opponent_card = get_card_in_slot(opponent_index)

    var attacker_slot = $Slots.get_children()[attacker_index]
    var opponent_slot = $Slots.get_children()[opponent_index]

    if attacking_card == null:
        push_error("There is no attacking card")

    if opponent_card == null:
        var victim = 1
        var damage = attacking_card.attack_day

        if slot_is_bottom(opponent_index):
            victim = 0
            damage = attacking_card.attack_night

        # Attack opponent.
        attacker_slot.attack(true)

        opponent_slot.damage_player(damage)
        emit_signal("player_attacked", victim, damage)
        return

    # Handel hier de abillities af

    # verediging - aanval
    var attack_result

    if slot_is_bottom(attacker_index):
        attack_result = (
            attacking_card.attack_day - opponent_card.defence_night)
    else:
        attack_result = (
            attacking_card.attack_night - opponent_card.defence_day)

    attacker_slot.attack(false)

    if attack_result >= 0:
        opponent_slot.destroy_card()

        # yield(slot, "card_destroyed")
        # emit_signal("action_ended", "attack", {})
    else:
        opponent_slot.deflect_attack()


func _on_Root_next_action(turn, player):
    player_attacking = false

    match turn:
        "rotate":
            rotate_board(1)

            yield(self, "rotation_complete")

            emit_signal("action_ended", turn, {})
        "place":
            if player > 0:
                emit_signal("action_ended", turn, {"skipped": true})
        "attack":
            print("Can opponent attack? ", opponent_can_attack())
            if player == 0 and player_can_attack():
                player_attacking = true
            elif player > 0 and opponent_can_attack():
                # TODO: Select random card and attack.
                perform_opponent_attack()
            else:
                emit_signal("action_ended", turn, {"skipped": true})


func _on_Root_next_turn(_player):
    for idx in range(2 * sectors):
        var card = get_card_in_slot(idx)

        if card == null:
            continue

        card.get_node("SleepParticles").handleTurnsToSleep()


func _on_CardSlot_slot_occupied(slot, card):
    emit_signal("action_ended", "place", {"slot": slot, "card": card})


func _on_CardSlot_slot_clicked(slot, _card):
    if not player_attacking:
        return

    var idx = $Slots.get_children().find(slot)

    if slot_is_bottom(idx):
        attack(idx)
        # slot.attack()

        yield(slot, "slot_attacked")

        emit_signal("action_ended", "attack", {})
