# Respuestas de prueba del script

Esta carpeta se llena ejecutando:

```bash
./scripts/capture_evidence.sh
```

Genera:

| Archivo | Contenido |
|---|---|
| `01_request_1_MISS.txt` | Primera llamada: cabecera `X-Cache: MISS` |
| `02_request_2_HIT.txt` | Misma llamada repetida: cabecera `X-Cache: HIT` |
| `03_s3_ls.txt` | Salida de `aws s3 ls` con el objeto bajo `results/` |

> Los archivos de evidencia **se generan cuando se despliega en una cuenta AWS**
