extends Translation
## Mayusculas de los botones de texto en la piel dieselpunk (docs/21 §17).
##
## Button no tiene `uppercase` como Label. Para que se vean en mayusculas sin
## tocar `Button.text` (las pruebas y el codigo comparan ese texto, y las claves
## de Tr no cambian), el boton usa un dominio de traduccion propio
## (CartoonTheme.caps_button) cuya unica "traduccion" es pasar a mayusculas lo
## que se pinta. El juego no usa TranslationServer para nada mas (los textos
## salen de Tr), asi que no pisa a nadie.
##
## Lo que no lleva al menos dos letras seguidas ("x2", "✕", "+", "12") se queda
## como esta.

static var _word: RegEx = null

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message)
	if _word == null:
		_word = RegEx.create_from_string("\\p{L}{2,}")
	if _word.search(s) == null:
		return src_message
	return StringName(s.to_upper())
