extends Node2D

# --- NASTAVENÍ OBRAZOVKY ---
var sirka = 450
var vyska = 800

# --- HERNÍ PROMĚNNÉ ---
var skore = 50
var nejvyssi_skore = 0
var obtiznost = 1.0
var casovac_boxu = 0.0
var game_over = false

# Cesta pro trvalé ukládání do paměti zařízení
const CESTA_K_ULOZENI = "user://save_game.dat"

# --- LASER A PIVOT ---
var laser_start = Vector2(225, 750)
var laser_aktualni = Vector2.ZERO
var laser_smer = Vector2.ZERO
var laser_leti = false
var rychlost_laseru = 1700.0

# Trail (stopa za laserem)
var laser_trail = []
var max_trail_delka = 8
var zasah_id_v_tomto_letu = []

# --- KRABICE (BOXY) ---
var boxy = []

func _ready():
	DisplayServer.window_set_size(Vector2i(sirka, vyska))
	nacti_nejvyssi_skore()
	
	# Zelené skóre (vlevo nahoře - s přibývajícími ciframi roste doprava)
	if has_node("CanvasLayer/LabelSkore"):
		$CanvasLayer/LabelSkore.add_theme_font_size_override("font_size", 26)
		$CanvasLayer/LabelSkore.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
		
		# Správné ukotvení přes celé rozhraní pro automatické roztahování textu
		$CanvasLayer/LabelSkore.anchor_left = 0.0
		$CanvasLayer/LabelSkore.anchor_right = 1.0
		$CanvasLayer/LabelSkore.offset_left = 25
		$CanvasLayer/LabelSkore.offset_right = -25
		$CanvasLayer/LabelSkore.offset_top = 25
		$CanvasLayer/LabelSkore.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		
	# Žluté nejlepší skóre (vpravo nahoře - s přibývajícími ciframi roste doleva)
	if has_node("CanvasLayer/LabelBest"):
		$CanvasLayer/LabelBest.add_theme_font_size_override("font_size", 26)
		$CanvasLayer/LabelBest.add_theme_color_override("font_color", Color(1.0, 0.6, 0.0))
		
		# Správné ukotvení přes celé rozhraní pro automatické tlačení textu doleva
		$CanvasLayer/LabelBest.anchor_left = 0.0
		$CanvasLayer/LabelBest.anchor_right = 1.0
		$CanvasLayer/LabelBest.offset_left = 25
		$CanvasLayer/LabelBest.offset_right = -25
		$CanvasLayer/LabelBest.offset_top = 25
		$CanvasLayer/LabelBest.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		
	if has_node("CanvasLayer/GameOverPanel"):
		$CanvasLayer/GameOverPanel.hide()
		
	aktualizuj_ui()

func _process(delta):
	if game_over:
		return

	# Rychlejší nárůst obtížnosti v čase
	obtiznost += delta * 0.08

	casovac_boxu += delta
	# Časovač pro vysokou hustotu padajících krabic
	if casovac_boxu > max(0.08, 0.45 - (obtiznost * 0.08)):
		pridej_box()
		casovac_boxu = 0.0

	# Aktualizace pozice laseru na začátku snímku
	var stara_pozice_laseru = laser_aktualni
	if laser_leti:
		laser_trail.append(laser_aktualni)
		if laser_trail.size() > max_trail_delka:
			laser_trail.pop_front()
		laser_aktualni += laser_smer * rychlost_laseru * delta
	else:
		if laser_trail.size() > 0:
			laser_trail.pop_front()

	# JEDINÝ SPOLEČNÝ CYKLUS PRO POHYB A KOLIZE (Ochrana proti falešnému odečítání)
	var aktualizovane_boxy = []
	for b in boxy:
		# Vyšší rychlost posunu (230)
		b["pozice"].y += (230.0 * obtiznost) * delta
		var box_rect = Rect2(b["pozice"], b["velikost"])
		
		# Kontrola, zda box trefil letící laser
		if laser_leti and zkontroluj_protnuti(stara_pozice_laseru, laser_aktualni, box_rect):
			if not b["id"] in zasah_id_v_tomto_letu:
				zasah_id_v_tomto_letu.append(b["id"])
				if b["typ"] == "plus":
					skore += b["hodnota"]
				else:
					skore -= b["hodnota"]
			continue # Trefený box zmizí z pole, nemůže propadnout

		# Kontrola propadnutí pod obrazovku (při AFK skóre nepadá)
		if b["pozice"].y >= vyska:
			continue
			
		aktualizovane_boxy.append(b)
		
	boxy = aktualizovane_boxy

	# Kontrola nárazu laseru do stěny
	if laser_leti:
		if laser_aktualni.x <= 5 or laser_aktualni.x >= sirka - 5 or laser_aktualni.y <= 5 or laser_aktualni.y >= vyska - 5:
			laser_start.x = clamp(laser_aktualni.x, 15, sirka - 15)
			laser_start.y = clamp(laser_aktualni.y, 15, vyska - 15)
			laser_leti = false

	# Rekord a Game Over
	if skore > nejvyssi_skore:
		nejvyssi_skore = skore
		uloz_nejvyssi_skore()

	if skore < 0:
		spust_game_over()

	aktualizuj_ui()
	queue_redraw()

func _input(event):
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.is_pressed():
			if game_over:
				reset_hry()
			elif not laser_leti:
				var cil_strelu = event.position
				var smer = cil_strelu - laser_start
				if rucni_smer_delka(smer) > 15:
					laser_smer = rucni_smer_normalizace(smer)
					laser_aktualni = laser_start
					laser_leti = true
					laser_trail = []
					zasah_id_v_tomto_letu = []

func zkontroluj_protnuti(p1: Vector2, p2: Vector2, rect: Rect2) -> bool:
	if rect.has_point(p1) or rect.has_point(p2):
		return true
	var udrzuje_bod = rect.intersection(Rect2(min(p1.x, p2.x), min(p1.y, p2.y), abs(p1.x - p2.x) + 1, abs(p1.y - p2.y) + 1))
	return udrzuje_bod.size.x > 0 and udrzuje_bod.size.y > 0

func pridej_box():
	var b_velikost = Vector2(48, 48)
	var nalezena_pozice = false
	var b_x = 0.0
	var b_y = 0.0
	
	# OCHRANA PROTI PŘEKRÝVÁNÍ: Až 15 pokusů na nalezení místa bez kolize
	for pokus in range(15):
		b_x = randi() % int(sirka - b_velikost.x)
		# VĚTŠÍ ROZSAH Y: Generování až 300px nad obrazovkou
		b_y = -b_velikost.y - (randi() % 300)
		
		var novy_rect = Rect2(Vector2(b_x, b_y), b_velikost)
		var kolize_detekovana = false
		
		for b in boxy:
			var existujici_rect = Rect2(b["pozice"], b["velikost"])
			if novy_rect.intersects(existujici_rect):
				kolize_detekovana = true
				break
				
		if not kolize_detekovana:
			nalezena_pozice = true
			break
	
	# Pokud je přeplněno a volné místo nebylo nalezeno, spawn přeskočíme
	if not nalezena_pozice:
		return
		
	var b_hodnota = (randi() % 15) + 5
	var b_typ = "plus" if randf() < 0.6 else "minus"
	
	var b_barva = Color(0.0, 0.75, 1.0) if b_typ == "plus" else Color(1.0, 0.25, 0.25)
	var b_glow = Color(0.0, 0.4, 0.8, 0.25) if b_typ == "plus" else Color(0.8, 0.1, 0.1, 0.25)
	var b_text = "+" + str(b_hodnota) if b_typ == "plus" else "-" + str(b_hodnota)
	
	boxy.append({
		"pozice": Vector2(b_x, b_y),
		"velikost": b_velikost,
		"hodnota": b_hodnota,
		"typ": b_typ,
		"barva": b_barva,
		"glow": b_glow,
		"text": b_text,
		"id": randi()
	})

func rucni_smer_delka(v: Vector2) -> float:
	return sqrt(v.x * v.x + v.y * v.y)

func rucni_smer_normalizace(v: Vector2) -> Vector2:
	var l = rucni_smer_delka(v)
	if l > 0:
		return Vector2(v.x / l, v.y / l)
	return Vector2.ZERO

func uloz_nejvyssi_skore():
	var soubor = FileAccess.open(CESTA_K_ULOZENI, FileAccess.WRITE)
	if soubor:
		soubor.store_32(nejvyssi_skore)
		soubor.close()

func nacti_nejvyssi_skore():
	if FileAccess.file_exists(CESTA_K_ULOZENI):
		var soubor = FileAccess.open(CESTA_K_ULOZENI, FileAccess.READ)
		if soubor:
			nejvyssi_skore = soubor.get_32()
			soubor.close()

# --- VYKRESLOVÁNÍ ---
func _draw():
	var barva_top = Color(0.05, 0.05, 0.12)
	var barva_bottom = Color(0.08, 0.08, 0.2)
	var body_pozadi = PackedVector2Array([Vector2(0, 0), Vector2(sirka, 0), Vector2(sirka, vyska), Vector2(0, vyska)])
	var barvy_pozadi = PackedColorArray([barva_top, barva_top, barva_bottom, barva_bottom])
	draw_polygon(body_pozadi, barvy_pozadi)

	var vychozi_font = Control.new().get_theme_font("font")

	if game_over:
		var text_go = "GAME OVER"
		var text_restart = "Klikni pro restart"
		draw_string(vychozi_font, Vector2((sirka / 2) - 120, (vyska / 2) - 16), text_go, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.8, 0.1, 0.1, 0.4))
		draw_string(vychozi_font, Vector2((sirka / 2) - 122, (vyska / 2) - 20), text_go, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.2, 0.2))
		draw_string(vychozi_font, Vector2((sirka / 2) - 90, (vyska / 2) + 30), text_restart, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.7, 0.8))
		return

	for b in boxy:
		# Vykreslí se jen tehdy, pokud je box už vidět na ploše
		if b["pozice"].y > -48:
			var rect = Rect2(b["pozice"], b["velikost"])
			draw_rect(rect.grow(4), b["glow"], false, 4.0)
			draw_rect(rect.grow(2), b["glow"], false, 2.0)
			draw_rect(rect, b["barva"], false, 2.5)
			draw_string(vychozi_font, b["pozice"] + Vector2(6, 31), b["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)

	if not laser_leti:
		var mys_pos = get_local_mouse_position()
		var vektor_smeru = mys_pos - laser_start
		if rucni_smer_delka(vektor_smeru) > 10:
			var smer_norm = rucni_smer_normalizace(vektor_smeru)
			var max_delka_uhlopricky = sqrt(sirka * sirka + vyska * vyska)
			var konec_zamerovace = laser_start + (smer_norm * max_delka_uhlopricky)
			draw_line(laser_start, konec_zamerovace, Color(0.2, 0.4, 0.6, 0.5), 1.5)
		
		draw_circle(laser_start, 14, Color(0.0, 0.5, 1.0, 0.2))
		draw_circle(laser_start, 10, Color(0.0, 0.75, 1.0))
		draw_circle(laser_start, 4, Color.WHITE)

	if laser_trail.size() > 1:
		for i in range(laser_trail.size() - 1):
			var koeficient_veku = float(i) / float(laser_trail.size())
			var tloustka = koeficient_veku * 4.5 + 1.0
			var barva_glow = Color(1.0, 0.4, 0.0, koeficient_veku * 0.3)
			var barva_stred = Color(1.0, 0.7, 0.0, koeficient_veku)
			draw_line(laser_trail[i], laser_trail[i+1], barva_glow, tloustka + 4.0)
			draw_line(laser_trail[i], laser_trail[i+1], barva_stred, tloustka)

	if laser_leti:
		draw_circle(laser_aktualni, 10, Color(0.2, 1.0, 0.4, 0.3))
		draw_circle(laser_aktualni, 6, Color(0.4, 1.0, 0.6))

func aktualizuj_ui():
	if has_node("CanvasLayer/LabelSkore") and has_node("CanvasLayer/LabelBest"):
		if game_over:
			$CanvasLayer/LabelSkore.hide()
			$CanvasLayer/LabelBest.hide()
		else:
			$CanvasLayer/LabelSkore.show()
			$CanvasLayer/LabelBest.show()
			
			# Vypisují se pouze čistá čísla
			$CanvasLayer/LabelSkore.text = str(max(0, skore))
			$CanvasLayer/LabelBest.text = str(nejvyssi_skore)

func spust_game_over():
	game_over = true
	boxy = []
	laser_trail = []
	aktualizuj_ui()

func reset_hry():
	skore = 50
	obtiznost = 1.0
	boxy = []
	laser_start = Vector2(225, 750)
	laser_leti = false
	game_over = false
	aktualizuj_ui()
