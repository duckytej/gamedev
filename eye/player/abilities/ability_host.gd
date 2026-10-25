class_name PlayerAbilityHost
extends Node3D

## Small registry for the optional modules on the player.
##
## The host exists so the player and the movement states never depend on a
## hard-coded scene path. Any child [PlayerAbility] with an `ability_id` can be
## added, removed or disabled independently.

var player: EyePlayer

var _abilities: Dictionary = {}
var _set_up := false


func setup(owner_player: EyePlayer) -> void:
	player = owner_player
	if _set_up:
		return
	_set_up = true

	_abilities.clear()
	for child in get_children():
		var ability := child as PlayerAbility
		if ability == null:
			continue
		if ability.ability_id == &"":
			push_warning("PlayerAbilityHost: '%s' has no ability_id." % ability.name)
			continue
		if _abilities.has(ability.ability_id):
			push_warning("PlayerAbilityHost: duplicate ability_id '%s'." % ability.ability_id)
			continue
		ability.setup(owner_player)
		_abilities[ability.ability_id] = ability


func get_ability(ability_id: StringName) -> PlayerAbility:
	var value: Variant = _abilities.get(ability_id)
	if not is_instance_valid(value):
		return null
	var ability := value as PlayerAbility
	if ability == null or not ability.enabled:
		return null
	return ability


func has_ability(ability_id: StringName) -> bool:
	return get_ability(ability_id) != null


func pre_move_update(delta: float) -> void:
	for ability in _abilities.values():
		if is_instance_valid(ability) and ability.enabled:
			ability.pre_move_update(delta)


func post_move_update(delta: float) -> void:
	for ability in _abilities.values():
		if is_instance_valid(ability) and ability.enabled:
			ability.post_move_update(delta)
