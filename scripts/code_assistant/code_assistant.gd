extends PanelContainer
var openai:OpenAIAPI
var bot_thinking:bool = false

@onready var copy_output_button = $vbox/hsplit/vbox2/hbox/copy_output_button
@onready var text_input = $vbox/hsplit/vbox/text_input
@onready var text_display = $vbox/hsplit/vbox2/text_display
@onready var generate_button = $vbox/hcon/generate_button
@onready var input_code_type = $vbox/hsplit/vbox/hbox/input_code_type
@onready var output_code_type = $vbox/hsplit/vbox2/hbox/output_code_type



@onready var loading = $vbox/hcon/loading
@onready var bad_status = preload("res://images/icons/bad_status.png")
@onready var good_status = preload("res://images/icons/good_status.png")
@onready var wait_status = preload("res://images/icons/wait_status.png")
@onready var nil_status = preload("res://images/icons/nil_status.png")

var logit_bias:Dictionary = {
	20185: -50, #AI
	3303: -80, #language
	2746: -80, #model
	562: -20, #ass
	10167: -80, #istant
}

var supported_languages:PackedStringArray = [
	"Assembly",
	"Brainfuck",
	"C",
	"C#",
	"C++",
	"Go",
	"Godot 3 GDscript",
	"Java",
	"Javascript",
	"Koltin",
	"Lua",
	"MicroPython",
	"PHP",
	"Python",
	"R",
	"Rust",
	"Swift",
	"Typescript"
]

func _ready():
	get_tree().get_root().files_dropped.connect(_files_dropped)
	bot_thinking = true
	loading.texture = wait_status
	copy_output_button.pressed.connect(copy_output)
	
	text_display.text = ""
	input_code_type.add_item("Detect")
	output_code_type.add_item("Match Input")
	for l in supported_languages:
		input_code_type.add_item(l)
		output_code_type.add_item(l)
	
	input_code_type.item_selected.connect(func(idx): change_input_type(idx, input_code_type, text_input))
	output_code_type.item_selected.connect(func(idx): change_input_type(idx, output_code_type, text_display))
	
	generate_button.pressed.connect(generate_code)
	
	await connect_openai()
	bot_thinking = false
	loading.texture = good_status

func change_input_type(idx:int, button:OptionButton, display:CodeEdit):
	var highlight:Node = display.get_child(0)
	match button.get_item_text(idx):
		"Javascript":
			highlight.set_script(load("res://scripts/code_assistant/code_highlighters/javascript_highlighter.gd"))
		"Godot 3 GDscript":
			highlight.set_script(load("res://scripts/code_assistant/code_highlighters/gdscript_highlighter.gd"))
		"Python":
			highlight.set_script(load("res://scripts/code_assistant/code_highlighters/python_highlighter.gd"))
		_:
			highlight.set_script(null)
	await get_tree().process_frame
	if(highlight.get_script() != null):
		highlight._ready()

func copy_output():
	if(bot_thinking):
		return
	if(text_display.text.strip_edges().strip_escapes().is_empty() || text_display.text == "Awaiting response..."):
		return
	DisplayServer.clipboard_set(text_display.text)

func connect_openai():
	await get_tree().process_frame
	openai = OpenAIAPI.new(get_tree(), "https://api.openai.com/v1/chat/", globals.API_KEY)
	openai.connect("request_success", _on_openai_request_success)
	openai.connect("request_error", _on_openai_request_error)


func generate_code():
	if(bot_thinking || text_input.text.strip_edges().is_empty()):
		return
	
	bot_thinking = true
	wait_blink()
	text_display.text = "Awaiting response..."
	
	var chat_array:Array = []
	
	chat_array.append({"role": "system", "content": globals.load_file_as_string("res://scripts/code_assistant/code_rules.txt")})
	if(input_code_type.get_item_text(input_code_type.selected) == "Detect"):
		chat_array.append({"role": "system", "content": "\nFigure out what scripting language is used from the user provided code."})
	else:
		chat_array.append({"role": "system", "content": "\nThe input text is in the language:" + input_code_type.get_item_text(input_code_type.selected)})
	if(output_code_type.get_item_text(output_code_type.selected) == "Match Input"):
		if(input_code_type.get_item_text(input_code_type.selected) == "Detect"):
			chat_array.append({"role": "system", "content": "\nKeep the same scripting language when you provide the corrected code."})
		else:
			chat_array.append({"role": "system", "content": "\nThe output scripting language is: " + input_code_type.get_item_text(input_code_type.selected)})
	else:
		chat_array.append({"role": "system", "content": "\nYou must port the provided code into the scripting language:" + output_code_type.get_item_text(output_code_type.selected)})
	chat_array.append({"role": "user", "content": text_input.text})
	
	print(chat_array)
	var data = {
	"model": globals.AI_MODEL,
	"messages": chat_array,
	"temperature": 0.3,
	"presence_penalty": 0.0,
	"frequency_penalty": 0.0,
	"stream": false,
	"logit_bias": logit_bias
	}
	
	openai.make_request("completions", HTTPClient.METHOD_POST, data)


func _on_openai_request_success(data):
	print(data)
	globals.TOTAL_TOKENS_USED += data.usage.total_tokens
	globals.TOTAL_TOKENS_COST += (data.usage.prompt_tokens*globals.INPUT_TOKENS_COST) + (data.usage.completion_tokens*globals.TOKENS_COST)
	
	text_display.text = data.choices[0].message.content
	
	bot_thinking = false
	loading.texture = good_status

func _on_openai_request_error(error_code):
	printerr("Request failed with error code:", error_code)
	text_display.text = globals.parse_api_error(error_code)
	bot_thinking = false
	loading.texture = bad_status

var wait_thread:Thread = Thread.new()
func wait_blink():
	while bot_thinking:
		loading.texture = wait_status
		await globals.delay(0.5)
		if(!bot_thinking):
			return
		loading.texture = nil_status
		await globals.delay(0.5)




func _files_dropped(files):
	print(files)
	var start:bool = true
	for f in files:
		var file:String = f
		if( globals.SCRIPT_EXTENSIONS.has(file.get_extension()) ):
			if(start):
				text_input.text = ""
				start = false
			text_input.text += globals.load_file_as_string(file)
		else:
			printerr("Invalid file type dropped: " + file)
	#token_estimation.text = "Token Estimation: " + str((globals.token_estimate(text_input.text)*2)+200) + " | "
