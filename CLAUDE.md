# gotenberg: notas para trabajar aquí

- Todo en español: commits, ramas, PR, comentarios y docs. Sin atribución a Claude.
- Nunca push a `main`: rama → PR → «Compilar» → merge de Rodrigo → «Publicar».
  Ningún PC da órdenes al VPS.
- Imagen fijada por versión **y** digest.
- Sin puertos ni entrada pública: se llega por las redes (internas) que crea
  materdev-infra (`domus-gotenberg`, …). No abrir `convert/url` a nadie (SSRF).
- Seguridad (ver README): redes internas, salida solo por `gotenberg-salida` (squid),
  sin JavaScript, ficheros solo de la petición y lo local bloqueado.
  `scripts/probar-ssrf.sh` tiene que pasar siempre.
  - No poner `--chromium-deny-private-ips`: en red interna lo rechaza todo.
  - En las expresiones de `--chromium-*-list`, nada de comas: Gotenberg corta por ahí.
