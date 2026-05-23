extends Node

# Companion behavior signals
signal companion_clicked

# Chat signals
signal chat_requested(message: String)
signal chat_response_received(message: String)
signal chat_bubble_closed

# true일 때 Companion의 passthrough 업데이트를 멈추고 창 전체를 interactive로 전환
var chat_input_open: bool = false
