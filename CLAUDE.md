# gotenberg: notas para trabajar aquí

- Todo en español: commits, ramas, PR, comentarios y docs. Sin atribución a Claude.
- Nunca push a `main`: rama → PR → «Compilar» → merge de Rodrigo → «Publicar».
  Ningún PC da órdenes al VPS.
- Imagen fijada por versión **y** digest.
- Sin puertos ni entrada pública: se llega por las redes que crea materdev-infra
  (`domus-gotenberg`, …). No abrir `convert/url` a nadie (SSRF).
