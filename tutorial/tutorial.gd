extends CenterContainer

var progress = 0


func _ready():
    if TutorialManager.tutorial_finished:
        queue_free()


func _on_Root_next_action(turn, _player):
    if TutorialManager.tutorial_finished:
        return

    visible = true

    for dialog in get_children():
        print(dialog.name)
        if turn == dialog.action:
            get_tree().paused = true
            dialog.popup()

            yield(dialog, "confirmed")
            dialog.queue_free()
            get_tree().paused = false

    visible = false

    if len(get_children()) == 0:
        print("Finished tutorial")
        TutorialManager.tutorial_finished = true
        queue_free()
