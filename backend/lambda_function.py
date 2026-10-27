"""
App "¿Qué rol tech eres?" (versión 2): backend en AWS Lambda (Python 3.13).

Rutas (HTTP API detrás de CloudFront, en el mismo dominio de la página, sin CORS):
  POST /api/rol    recibe el nombre y el índice de la opción elegida en cada pregunta. Calcula aquí el rol
                   (el navegador ya no decide qué se cuenta), pide a Bedrock el perfil en JSON, lo valida y
                   suma 1 al rol en DynamoDB.
  GET  /api/stats  cuántas personas obtuvieron cada rol: lo lee el tablero del proyector.

Variables de entorno:
  MODEL_ID           el modelo que escribe el perfil: Claude Haiku 4.5 (el que mejor actúa el PERSONAJE)
  MODEL_ID_RESPALDO  si el primero frena por cuota o falla, responde este: Amazon Nova Lite
  TABLE_NAME         tabla del contador
  PERSONAJE          cómo habla la IA. Cambiarlo en la consola es la demo en vivo, sin tocar el código.

Por qué dos modelos: en la cuenta de laboratorio, el 26-oct-2026, Haiku 4.5 tenía una cuota de 10 peticiones
por minuto y Nova Lite de 200. Haiku actúa el personaje (el narrador de fútbol grita "¡GOOOL!"); Nova Lite
apenas lo nota, pero aguanta un auditorio. Si los dos fallan, queda el texto de respaldo.

Las preguntas y los roles vienen de preguntas.json, el mismo archivo que lee la página.
"""

import json
import os
import random
import re
import time

import boto3
from botocore.config import Config

MODELOS = [m for m in (os.environ.get("MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0"),
                        os.environ.get("MODEL_ID_RESPALDO", "us.amazon.nova-lite-v1:0")) if m]
NOMBRES_MODELO = {"anthropic.claude-haiku-4-5": "Claude Haiku 4.5", "amazon.nova-lite": "Amazon Nova Lite",
                  "amazon.nova-2-lite": "Amazon Nova 2 Lite", "anthropic.claude-sonnet-4-6": "Claude Sonnet 4.6"}
TABLE_NAME = os.environ.get("TABLE_NAME", "rol-tech-stats")

with open(os.path.join(os.path.dirname(__file__), "preguntas.json"), encoding="utf-8") as f:
    DATOS = json.load(f)
ROLES = DATOS["roles"]
PREGUNTAS = DATOS["preguntas"]

# Sin reintentos del SDK: si el primer modelo frena por cuota, el siguiente responde de inmediato. Esperar
# y reintentar el mismo modelo dejaría al estudiante mirando la pantalla de carga.
bedrock = boto3.client("bedrock-runtime", config=Config(connect_timeout=3, read_timeout=12, retries={"max_attempts": 1}))
table = boto3.resource("dynamodb").Table(TABLE_NAME)

# Lo que tiene que traer el JSON de la IA, con el tipo y el largo máximo de cada clave.
CLAVES = {"titulo": 80, "descripcion": 400, "superpoder": 160, "servicios_aws": 3, "primer_paso": 240}


def system_prompt():
    """Se arma en cada petición para que el cambio de PERSONAJE se note de inmediato."""
    # La voz del personaje se pide de forma explícita, y se repite en el pedido (generar_perfil).
    return (
        f"Eres {personaje()}. Hablas con estudiantes universitarios de Colombia y escribes SIEMPRE con la voz de "
        "ese personaje: sus expresiones, su tono y su energía se tienen que notar en cada frase. "
        "Escribes en español, con humor sano, sin groserías y sin estereotipos. "
        "Respondes SOLO con un objeto JSON válido, sin texto adicional ni bloques de código."
    )


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "")
    path = event.get("rawPath", "")
    if method == "GET" and path.endswith("/stats"):
        return get_stats()
    if method == "POST" and path.endswith("/rol"):
        return post_rol(event)
    return respond(404, {"error": "Ruta no encontrada"})


def post_rol(event):
    inicio = time.time()
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return respond(400, {"error": "El cuerpo debe ser JSON"})

    # Una respuesta por pregunta: el índice de la opción (0 a 3). Nada de texto libre en el prompt.
    respuestas = body.get("respuestas")
    if not (isinstance(respuestas, list) and len(respuestas) == len(PREGUNTAS)
            and all(type(r) is int and 0 <= r < len(p["o"]) for r, p in zip(respuestas, PREGUNTAS))):
        return respond(400, {"error": "Se esperan 8 respuestas, cada una el número de la opción elegida"})

    nombre = limpiar(body.get("nombre", ""), 24) or "Estudiante"
    elegidas = [p["o"][r] for r, p in zip(respuestas, PREGUNTAS)]  # [texto, rol]
    rol = calcular_rol([r for _, r in elegidas])

    # 1) Perfil personalizado con IA generativa (Amazon Bedrock)
    t_ia = time.time()
    perfil, fuente, modelo = generar_perfil(nombre, rol, [t for t, _ in elegidas])
    ms_ia = int((time.time() - t_ia) * 1000)

    # 2) Contador atómico en DynamoDB para el tablero en vivo.
    #    "total" es palabra reservada de DynamoDB: va con un alias (#total), o la escritura falla.
    try:
        table.update_item(Key={"rol": rol}, UpdateExpression="ADD #total :uno",
                          ExpressionAttributeNames={"#total": "total"}, ExpressionAttributeValues={":uno": 1})
    except Exception as e:  # la demo sigue aunque falle el conteo, pero queda en el log
        print(json.dumps({"evento": "error_dynamodb", "detalle": str(e)[:200]}, ensure_ascii=False))

    # Una línea de log por estudiante: se ve en vivo con CloudWatch Live Tail
    print(json.dumps({"evento": "nuevo_resultado", "nombre": nombre, "rol": ROLES[rol]["nombre"], "fuente": fuente,
                      "modelo": modelo, "ia_ms": ms_ia}, ensure_ascii=False))

    return respond(200, {
        "rol": rol,
        "rolNombre": ROLES[rol]["nombre"],
        "perfil": perfil,
        "fuente": fuente,  # "bedrock" o "respaldo"
        "modelo": modelo,  # qué modelo escribió el perfil (None si fue el texto de respaldo)
        "tiempos": {"ia_ms": ms_ia, "total_ms": int((time.time() - inicio) * 1000)},
    })


def calcular_rol(roles_elegidos):
    """El rol con más puntos; si empatan, uno de los empatados al azar (igual que hacía el navegador)."""
    puntos = {k: 0 for k in ROLES}
    for r in roles_elegidos:
        puntos[r] += 1
    maximo = max(puntos.values())
    return random.choice([k for k, v in puntos.items() if v == maximo])


def personaje():
    return os.environ.get("PERSONAJE", "un mentor tech divertido")[:200]


def generar_perfil(nombre, rol, textos):
    prompt = (
        f"Un estudiante llamado {nombre} hizo un test de personalidad tech y su resultado fue "
        f"'{ROLES[rol]['nombre']}'. Estas fueron sus respuestas: {'; '.join(textos)}.\n\n"
        f"Escribe cada valor como lo diría {personaje()}, que se note desde la primera palabra.\n"
        "Devuelve un JSON con exactamente estas claves:\n"
        '"titulo": un apodo creativo y corto para su perfil (máximo 6 palabras),\n'
        '"descripcion": 2 frases divertidas que conecten sus respuestas con el rol,\n'
        '"superpoder": una frase corta con su mayor fortaleza,\n'
        '"servicios_aws": lista de 3 servicios de AWS que debería aprender para este rol,\n'
        '"primer_paso": una acción concreta que pueda hacer esta semana para empezar.'
    )
    for modelo_id in MODELOS:
        try:
            r = bedrock.converse(
                modelId=modelo_id,
                system=[{"text": system_prompt()}],
                messages=[{"role": "user", "content": [{"text": prompt}]}],
                inferenceConfig={"maxTokens": 400},  # sin temperature: desde Claude 4.7 da error 400
            )
            # El texto es el primer bloque que trae "text": un modelo que razona abre con otro tipo de bloque.
            texto = next(b["text"] for b in r["output"]["message"]["content"] if "text" in b)
            return validar(json.loads(extraer_json(texto))), "bedrock", nombre_modelo(modelo_id)
        except Exception as e:  # ThrottlingException (cuota), un JSON inválido, un modelo sin acceso...
            print(json.dumps({"evento": "error_bedrock", "modelo": modelo_id, "tipo": type(e).__name__,
                              "detalle": str(e)[:200]}, ensure_ascii=False))
    return respaldo(rol), "respaldo", None


def nombre_modelo(modelo_id):
    return next((n for clave, n in NOMBRES_MODELO.items() if clave in modelo_id), modelo_id)


def extraer_json(texto):
    """Del primer '{' al último '}': aguanta un modelo que envuelve el JSON en ``` o agrega una frase."""
    ini, fin = texto.find("{"), texto.rfind("}")
    if ini < 0 or fin <= ini:
        raise ValueError("la respuesta no trae un objeto JSON")
    return texto[ini:fin + 1]


def validar(perfil):
    """Solo pasa a la pantalla un JSON con las cinco claves, del tipo correcto y de un largo razonable."""
    if not isinstance(perfil, dict):
        raise ValueError("el JSON no es un objeto")
    limpio = {}
    for clave, largo in CLAVES.items():
        valor = perfil.get(clave)
        if clave == "servicios_aws":
            if not isinstance(valor, list) or not all(isinstance(s, str) and s.strip() for s in valor):
                raise ValueError("servicios_aws no es una lista de textos")
            limpio[clave] = [s.strip()[:40] for s in valor][:largo]
        else:
            if not isinstance(valor, str) or not valor.strip():
                raise ValueError(f"falta {clave}")
            limpio[clave] = valor.strip()[:largo]
    return limpio


def respaldo(rol):
    """Texto de respaldo si Bedrock no responde o responde algo inválido: la demo nunca se queda en blanco."""
    return {
        "titulo": f"{ROLES[rol]['nombre']} en formación",
        "descripcion": ROLES[rol]["desc"],
        "superpoder": "Curiosidad sin límites",
        "servicios_aws": ROLES[rol]["servicios"],
        "primer_paso": "Crea tu cuenta en AWS Skill Builder y toma el curso Cloud Practitioner Essentials.",
    }


def get_stats():
    conteos = {k: 0 for k in ROLES}
    try:
        for item in table.scan().get("Items", []):
            if item.get("rol") in conteos:
                conteos[item["rol"]] = int(item.get("total", 0))
    except Exception as e:
        print(json.dumps({"evento": "error_dynamodb", "detalle": str(e)[:200]}, ensure_ascii=False))
    return respond(200, {"conteos": conteos, "nombres": {k: v["nombre"] for k, v in ROLES.items()},
                         "total": sum(conteos.values())})


def limpiar(valor, largo):
    """Quita caracteres raros y limita el largo del nombre, el único texto libre que llega al prompt."""
    texto = re.sub(r"[^\w\sáéíóúÁÉÍÓÚñÑüÜ.,¿?¡!-]", "", str(valor))
    return texto.strip()[:largo]


def respond(status, data):
    # Sin cabeceras CORS: la página y la API salen del mismo dominio de CloudFront.
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"},
        "body": json.dumps(data, ensure_ascii=False),
    }
