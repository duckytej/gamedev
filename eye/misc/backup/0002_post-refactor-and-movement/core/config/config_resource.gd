class_name ConfigResource
extends Resource

## Base class for data-only tuning resources.
##
## Subclasses expose `@export` fields and an `apply_to(target)`. This helper
## assigns a dictionary onto any target and warns (instead of silently doing
## nothing) when a key is missing, so config resources stay decoupled from the
## nodes they configure.
##
## This is the whole "framework": resources carry data, code reads it. New
## systems follow the same pattern (see `docs/ARCHITECTURE.md`).


static func apply_values(target: Object, values: Dictionary) -> void:
	if target == null:
		push_warning("ConfigResource.apply_values: target is null.")
		return

	var valid := {}
	for prop in target.get_property_list():
		valid[prop.name] = true

	for key in values:
		if valid.has(key):
			target.set(key, values[key])
		else:
			push_warning("ConfigResource: '%s' is not a property of %s." % [key, target])


## Override in subclasses.
func apply_to(_target: Object) -> void:
	push_error("ConfigResource.apply_to(): override this in the subclass.")
