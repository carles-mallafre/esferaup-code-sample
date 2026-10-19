"""Editable-prompt registry — the source of truth for which prompts the admin panel exposes,
their code-side defaults, placeholders, and whether they require clinical sign-off.

Authoring prompts (Activa Studio) carry NO child data → editable directly. Insight prompts
(AI Patrons) run over child data → ``requires_signoff`` (a clinical advisor must approve an
edit before it goes live). The DB (``ai_prompts``) overrides these defaults per prompt_id.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class PromptSpec:
    prompt_id: str
    label: str
    description: str
    default: str
    requires_signoff: bool
    placeholders: tuple[str, ...] = field(default_factory=tuple)


_ACTIVA_SKELETON = (
    "Proposa exactament {n} títols d'exercici (curts, < 8 paraules) per a un pla "
    "d'aprenentatge sobre: «{brief}». Retorna NOMÉS una llista numerada, un títol per línia."
)
_ACTIVA_IMPROVE_INSTRUCTION = "Millora i fes més clar aquest text per a infants"
_ACTIVA_GENERATE_PLAN = (
    "Ets un assistent d'autoria de quaderns d'exercicis per a infants (fascicles "
    "mensuals en paper). A partir de la descripció següent, construeix els exercicis "
    "del primer fascicle.\n\nDescripció de l'autor:\n«{brief}»\n\n"
    "Retorna NOMÉS un objecte JSON vàlid (sense text al voltant, sense code fences) amb "
    "aquesta forma exacta:\n"
    '{{"exercises": [{{"name": "...", "estimated_minutes": 10, "tematica": "...", '
    '"blocks": [{{"content_type_key": "...", "data": {{...}}}}]}}]}}\n\n'
    '"tematica" és OBLIGATÒRIA per a cada exercici; tria\'n una de: atencio, '
    "lectura, mates, mindfulness, llenguatge, coordinacio, memoria, creativitat, "
    "emocions, activa.\n\n"
    "Tipus de bloc permesos i la forma del seu data (els camps de text són objectes "
    'per-idioma {{"ca": "...", "es": "...", "en": "..."}} — omple els tres). Tots '
    'accepten un camp opcional "enunciat" (LocText) amb la consigna impresa:\n'
    '- free_text: {{"enunciat": LocText, "body": LocText}} — text lliure o conte curt\n'
    '- image: {{"enunciat": LocText, "description": LocText}} — descripció de la '
    "il·lustració desitjada (normalment lligada al conte)\n"
    '- questions_text: {{"enunciat": LocText, "questions": LocText}} — preguntes '
    "obertes, UNA PER LÍNIA dins de cada idioma\n"
    '- questions_choice: {{"enunciat": LocText, "questions": [{{"prompt": LocText, '
    '"options": [LocText, LocText, LocText, LocText], "correct": 0}}]}} — tipus test '
    "A/B/C/D\n"
    '- word_search: {{"enunciat": LocText, "words": ["...", ...], "grid_size": 10}} — '
    "sopa de lletres\n"
    '- operations: {{"enunciat": LocText, "kind": "suma|resta|multiplicacio|divisio|'
    'series", "items": ["12 + 7", ...]}} — operacions matemàtiques\n'
    '- drawing: {{"enunciat": LocText}} — espai perquè l\'infant dibuixi\n'
    '- sanefa: {{"enunciat": LocText, "description": LocText, "start": LocText, '
    '"direction": LocText}} — com és la sanefa, on comença i en quina direcció\n'
    '- mindfulness: {{"enunciat": LocText, "app_ref": '
    '"esferaup://activa/activity/breathing", "duration_minutes": 5}} — exercici guiat '
    "des de l'app\n"
    '- activation: {{"enunciat": LocText, "app_ref": '
    '"esferaup://activa/activity/movement", "duration_minutes": 5}} — activació '
    "corporal guiada des de l'app\n"
    '- writing: {{"enunciat": LocText, "content": "a A 1 2", "repetitions": 3}} — '
    "pràctica d'escriptura de lletres i nombres\n\n"
    "Respecta el nombre i el tipus d'exercicis que la descripció demani; si no ho "
    "especifica, proposa entre 4 i 8 exercicis variats (combina temàtiques). Màxim 20 "
    "exercicis i 8 blocs per exercici. Per als blocs d'app, app_ref ha de seguir "
    "exactament esferaup://activa/activity/<slug-segur> (minúscules, nombres i guions) "
    "i duration_minutes ha de ser un enter entre 1 i 480. To amable, sense "
    "culpabilitzar, sense pressa, "
    "sense llenguatge de diagnòstic."
)
_LUMA_COMPREHENSION = (
    "Eres un maestro de primaria que prepara preguntas de comprensión lectora para un niño o "
    "una niña de 6 a 12 años que acaba de leer el texto de abajo. Muchos de estos lectores "
    "tienen dislexia: escribe con frases cortas y palabras sencillas.\n"
    "Escribe entre 3 y 6 preguntas (menos si el texto es corto) en {language}, "
    "el idioma del texto.\n"
    "Reglas:\n"
    "- Cada pregunta se responde SOLO con lo que dice el texto. Mezcla preguntas literales "
    "(qué, quién, dónde, cuándo) con alguna de inferencia sencilla.\n"
    "- Sin dobles negaciones, sin trampas y sin preguntas sobre el significado de una sola letra.\n"
    "- 4 opciones cortas por pregunta; solo una es correcta y las otras son claramente "
    "incorrectas según el texto.\n"
    '- "evidence": copia LITERAL de la frase del texto donde está la respuesta, sin cambiar '
    "ni una letra.\n"
    "- No preguntes por datos personales (direcciones, teléfonos, salud, familia real) aunque "
    "aparezcan en el texto.\n"
    "- No valores al lector ni hables de dificultades, diagnósticos, puntos, premios o rachas.\n"
    "Devuelve SOLO JSON con esta forma: "
    '{{"questions":[{{"prompt":"...","options":["...","...","...","..."],"answer":0,'
    '"evidence":"..."}}]}}\n'
    "TEXTO:\n<<<\n{text}\n>>>"
)
_ACTIVA_IMAGE_FRAMING = (
    "Il·lustració infantil, estil amable i net, colors suaus, sense text ni paraules. "
    "Tema: {prompt}"
)

REGISTRY: dict[str, PromptSpec] = {
    "activa.skeleton": PromptSpec(
        prompt_id="activa.skeleton",
        label="Activa · esborrany d'exercicis",
        description="Suggereix títols d'exercici a partir d'un breu. Sense dades d'infants.",
        default=_ACTIVA_SKELETON,
        requires_signoff=False,
        placeholders=("n", "brief"),
    ),
    "activa.improve_instruction": PromptSpec(
        prompt_id="activa.improve_instruction",
        label="Activa · instrucció per defecte de «millora el text»",
        description="La instrucció que s'usa quan l'autor no n'especifica cap.",
        default=_ACTIVA_IMPROVE_INSTRUCTION,
        requires_signoff=False,
    ),
    "activa.generate_plan": PromptSpec(
        prompt_id="activa.generate_plan",
        label="Studio · Genera el pla des d'una descripció",
        description=(
            "Construeix el pla sencer (exercicis + blocs tipats) a partir del text que "
            "l'autor enganxa. La sortida ha de ser JSON estricte."
        ),
        default=_ACTIVA_GENERATE_PLAN,
        requires_signoff=False,
        placeholders=("brief",),
    ),
    "activa.image_framing": PromptSpec(
        prompt_id="activa.image_framing",
        label="Activa · estil d'il·lustració",
        description="El marc d'estil que s'afegeix a cada prompt d'imatge generada.",
        default=_ACTIVA_IMAGE_FRAMING,
        requires_signoff=False,
        placeholders=("prompt",),
    ),
    "luma.comprehension_questions": PromptSpec(
        prompt_id="luma.comprehension_questions",
        label="Luma · preguntes de comprensió després de llegir",
        description=(
            "Crea de 3 a 6 preguntes de resposta múltiple sobre un text que un infant ha "
            "escanejat o enganxat al lector de Luma. Contingut per a infants: cal signatura."
        ),
        default=_LUMA_COMPREHENSION,
        requires_signoff=True,
        placeholders=("language", "text"),
    ),
    "insight_family_weekly": PromptSpec(
        prompt_id="insight_family_weekly",
        label="AI Patrons · resum setmanal (dades d'infants)",
        description="Insight setmanal per a la família. Requereix signatura clínica.",
        default="",  # loaded from the YAML store lazily
        requires_signoff=True,
    ),
    "insight_outburst_tip": PromptSpec(
        prompt_id="insight_outburst_tip",
        label="AI Patrons · consell d'esclat (dades d'infants)",
        description="Consell puntual per a la família. Requereix signatura clínica.",
        default="",
        requires_signoff=True,
    ),
}


def default_content(spec: PromptSpec) -> str:
    """The code-side default; insight prompts fall back to their YAML system_prompt."""
    if spec.default:
        return spec.default
    try:
        from app.ai.prompts import get_prompt

        return get_prompt(spec.prompt_id).system_prompt
    except Exception:
        return ""
