extends Node

# Companion behavior signals
signal companion_clicked
signal mouse_near_companion(distance: float)
signal mouse_far_from_companion

# State signals
signal state_changed(from: String, to: String)
signal emotion_changed(emotion_name: String, value: float)

# Chat signals
signal chat_requested(message: String)
signal chat_response_received(message: String)

# true일 때 Companion의 passthrough 업데이트를 멈추고 창 전체를 interactive로 전환
var chat_input_open: bool = false
