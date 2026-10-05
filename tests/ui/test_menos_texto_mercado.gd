extends GdUnitTestSuite
## El Mercado con menos texto (2026-10-04): cada fila es el icono del recurso
## (su nombre en el tooltip), los dos precios y los botones; el oro, icono y
## cifra. Lo que decide —precio de compra y de venta— sigue a la vista.

func test_each_row_keeps_both_prices_and_names_the_resource_in_its_tooltip() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/MarketPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	panel._toggle_panel()
	for res_name in panel._rows:
		var row: Control = panel.find_child("Row_" + res_name, true, false)
		assert_object(row).is_not_null()
		var icon: Control = row.find_child("ResIcon", true, false)
		assert_str(icon.tooltip_text).is_equal(Tr.res_cap(res_name))
		assert_str(panel._rows[res_name]["buy_price"].text).is_equal(str(MarketManager.get_buy_price(res_name)))
		assert_str(panel._rows[res_name]["sell_price"].text).is_equal(str(MarketManager.get_sell_price(res_name)))
	var gold: Label = panel.find_child("GoldLabel", true, false)
	assert_str(gold.text).is_equal(str(ResourceManager.get_amount(ResourceManager.Type.GOLD)))
	panel._toggle_panel()
