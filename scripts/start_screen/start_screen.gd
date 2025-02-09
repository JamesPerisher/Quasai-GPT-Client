extends PanelContainer
@onready var openai_status:Button = $mcon/vbox/hbox2/openai_status
@onready var status_icon = $mcon/vbox/hbox2/status_icon

@onready var settings_button = $mcon/vbox/hbox2/settings_button
@onready var settings_popup = $settings_popup
@onready var openai_api_key_input = $"settings_popup/tabs/Model Settings/vbox/openai_api_key_input"
@onready var model_options_button = $"settings_popup/tabs/Model Settings/vbox/model_options_button"
@onready var model_blurb = $"settings_popup/tabs/Model Settings/vbox/model_blurb"

@onready var clear_stats_button = $settings_popup/tabs/Stats/vbox/clear_stats_button
@onready var total_tokens_display = $settings_popup/tabs/Stats/vbox/total_tokens_display
@onready var total_cost_display = $settings_popup/tabs/Stats/vbox/total_cost_display



var openai:OpenAIAPI
var config = ConfigFile.new()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()
		get_tree().quit()
		return

func _ready():
	load_config()
	settings_popup.hide()
	settings_popup.confirmed.connect(save_settings)
	settings_button.pressed.connect(open_settings)
	clear_stats_button.pressed.connect(clear_stats)
	openai_status.pressed.connect(func(): OS.shell_open("https://status.openai.com/"))
	openai_status.text = "Checking OpenAI Status..."
	$"settings_popup/tabs/Model Settings/vbox/open_user_folder".pressed.connect(func(): OS.shell_open(ProjectSettings.globalize_path("user://")))
	openai_api_key_input.text = globals.API_KEY
	model_options_button.add_item("GPT 3.5 Turbo")
	model_options_button.add_item("GPT 4 - 8k")
	model_options_button.add_item("GPT 4 - 32k")
	model_options_button.set_item_disabled(2, true)
	model_options_button.item_selected.connect(ai_model_select)
	
	globals.AI_MODEL = config.get_value("Settings", "MODEL")
	match config.get_value("Settings", "MODEL"):
		"gpt-3.5-turbo":
			model_options_button.select(0)
			ai_model_select(0)
		"gpt-4":
			model_options_button.select(1)
			ai_model_select(1)
		_:
			model_options_button.select(0)
			ai_model_select(0)
	
	
	total_tokens_display.text = "Total tokens used: " + str(globals.TOTAL_TOKENS_USED)
	total_cost_display.text = "Total token cost: $" + str(globals.TOTAL_TOKENS_COST)
	
	await get_tree().process_frame
	await connect_openai()


func connect_openai():
	if(globals.API_KEY.is_empty()):
		openai_status.text = "API key is empty."
		status_icon.texture = preload("res://images/icons/bad_status.png")
		return
	
	status_icon.texture = preload("res://images/icons/wait_status.png")
	
	await get_tree().process_frame
	openai = OpenAIAPI.new(get_tree(), "https://api.openai.com/v1/chat/", globals.API_KEY)
	openai.request_success.connect(_on_openai_request_success)
	openai.request_error.connect(_on_openai_request_error)
	
	var data = {
	"model": globals.AI_MODEL,
	"messages": [{"role": "system", "content": ""}],
	"max_tokens": 1,
	"temperature": 0.0,
	"presence_penalty": 2.0,
	"frequency_penalty": 2.0,
	"stop": "",
	"stream": false
	}
	
	openai.make_request("completions", HTTPClient.METHOD_POST, data)

func _on_openai_request_success(data):
	print(data)
	globals.TOTAL_TOKENS_USED += data.usage.total_tokens
	globals.TOTAL_TOKENS_COST += (data.usage.prompt_tokens*globals.INPUT_TOKENS_COST) + (data.usage.completion_tokens*globals.TOKENS_COST)
	openai_status.text = "OpenAI servers operational"
	status_icon.texture = preload("res://images/icons/good_status.png")

func _on_openai_request_error(error_code):
	printerr("Request failed with error code:", error_code)
	status_icon.texture = preload("res://images/icons/bad_status.png")
	openai_status.text = globals.parse_api_error(error_code, true)

func load_config():
	var err = config.load("user://settings.cfg")
	if err != OK:
		printerr(err)
		return false
	return true


func open_settings():
	print(globals.TOTAL_TOKENS_USED)
	total_tokens_display.text = "Total tokens used: " + str(globals.TOTAL_TOKENS_USED)
	total_cost_display.text = "Total token cost: $" + str(globals.TOTAL_TOKENS_COST)
	settings_popup.popup_centered(Vector2i(400, 400))

func save_settings():
	if(!openai_api_key_input.text.strip_edges().is_empty()):
		globals.API_KEY = openai_api_key_input.text
	
	
	config.set_value("Settings", "API_KEY", globals.API_KEY)
	
	config.set_value("Stats", "TOTAL_TOKENS_USED", globals.TOTAL_TOKENS_USED)
	config.set_value("Stats", "TOTAL_TOKENS_COST", globals.TOTAL_TOKENS_COST)
	config.set_value("Settings", "MODEL", globals.AI_MODEL)
	config.save("user://settings.cfg")
	
	connect_openai()

func clear_stats():
	globals.TOTAL_TOKENS_USED = 0
	globals.TOTAL_TOKENS_COST = 0.0
	
	total_tokens_display.text = "Total tokens used: " + str(globals.TOTAL_TOKENS_USED)
	total_cost_display.text = "Total token cost: $" + str(globals.TOTAL_TOKENS_COST)
	
	save_settings()


func ai_model_select(id:int):
	match model_options_button.get_item_text(model_options_button.selected):
		"GPT 3.5 Turbo":
			globals.AI_MODEL = "gpt-3.5-turbo"
			globals.INPUT_TOKENS_COST = 0.000002
			globals.TOKENS_COST = 0.000002
			model_blurb.text = "GPT-3.5 Turbo: The fastest and cheapest model to use. Although GPT-4 can perform some tasks significantly better, GPT-3.5 should still be suitable for 70% of tasks without the substantial cost.\nCosts $0.002 per 1k tokens."
		"GPT 4 - 8k":
			globals.AI_MODEL = "gpt-4"
			globals.INPUT_TOKENS_COST = 0.00003
			globals.TOKENS_COST = 0.00006
			model_blurb.text = "GPT-4: GPT-4 is still in beta and requires an approved account for use. It is more advanced than GPT-3.5 but comes at the cost of being slower and having a higher token cost. This version allows for 8k tokens to be used in one request/message.\nCosts approximately $0.005 per 1k tokens."
		"GPT 4 - 32k":
			globals.AI_MODEL = "gpt-4-32k"
			globals.INPUT_TOKENS_COST = 0.00006
			globals.TOKENS_COST = 0.00012
		_:
			globals.AI_MODEL = "gpt-3.5-turbo"
			globals.INPUT_TOKENS_COST = 0.000002
			globals.TOKENS_COST = 0.000002
			model_blurb.text = "GPT 3.5 Turbo: The fastest and cheapest model to use. While GPT 4 can perform some tasks a lot better, GPT 3.5 should still work for 70% of tasks without the large cost.\nCosts $0.002 per 1k tokens."
	print(globals.AI_MODEL)

