Diagrama conceptual

                         ┌──────────────────────┐
                         │    KairoSetup.exe    │
                         │      ~125 MB         │
                         │  PostgreSQL NO está   │
                         │      embebido        │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    Kairo Installer   │
                         │       Wizard         │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ ¿Modo Cliente?       │
                         └──────────┬───────────┘
                              ┌─────┴─────┐
                             SÍ           NO
                              │            │
                              ▼            ▼
                     ┌─────────────┐  ┌──────────────────────┐
                     │ PostgreSQL  │  │ ¿PostgreSQL detectado│
                     │ no necesario│  │       localmente?    │
                     └──────┬──────┘  └──────────┬───────────┘
                            │                 ┌───┴───┐
                            │                SÍ       NO
                            │                 │        │
                            │                 ▼        ▼
                            │       ┌──────────────┐ ┌────────────────────┐
                            │       │ Detectar     │ │ PostgreSQL no      │
                            │       │ instancia    │ │ encontrado         │
                            │       │ real         │ └─────────┬──────────┘
                            │       └──────┬───────┘           │
                            │              │                   ▼
                            │              │        ┌────────────────────┐
                            │              │        │ ¿Descargar desde   │
                            │              │        │ GitHub?             │
                            │              │        └─────────┬──────────┘
                            │              │             ┌────┴────┐
                            │              │            SÍ         NO
                            │              │             │          │
                            │              │             ▼          ▼
                            │              │    ┌──────────────┐ ┌───────────┐
                            │              │    │ Descargar    │ │ Avisar    │
                            │              │    │ + SHA-256    │ │ y permitir│
                            │              │    │ + instalar   │ │ continuar  │
                            │              │    └──────┬───────┘ └─────┬─────┘
                            │              │           │               │
                            │              └───────────┴───────┬───────┘
                            │                                  │
                            ▼                                  ▼
                 ┌────────────────────────────────────────────────────┐
                 │              Configuración DB                      │
                 │                                                    │
                 │ Host:      localhost                              │
                 │ Puerto:    5432 / detectado                       │
                 │ Usuario:   postgres                               │
                 │ Contraseña: ********                              │
                 │                                                    │
                 │ [ Probar conexión ]                               │
                 └────────────────────────┬───────────────────────────┘
                                          │
                                ┌─────────┴─────────┐
                                │                   │
                               OK                 ERROR
                                │                   │
                                ▼                   ▼
                      ┌──────────────────┐  ┌──────────────────┐
                      │ Configurar Kairo │  │ Mostrar error    │
                      │ appsettings.json │  │ y permitir       │
                      │ + DB             │  │ corregir datos   │
                      └────────┬─────────┘  └────────┬─────────┘
                               │                     │
                               └──────────┬──────────┘
                                          │
                                          ▼
                              ┌────────────────────────┐
                              │ Instalación completada │
                              └────────────┬───────────┘
                                           │
                                           ▼
                              ┌────────────────────────┐
                              │     Kairo Updater       │
                              │                        │
                              │ frontend.zip           │
                              │ backend.zip             │
                              │                        │
                              │ PostgreSQL NO participa │
                              └────────────────────────┘

Quiero que implementes una mejora importante en el sistema actual de instalación de Kairo.

NO quiero que empieces modificando código inmediatamente. Primero revisa la implementación actual completa del instalador, `publish.bat`, manifiestos, updater y toda la lógica relacionada con PostgreSQL. Quiero que entiendas el flujo existente y después implementes esta arquitectura sin romper comportamiento existente.

# OBJETIVO

Actualmente `KairoSetup.exe` embebe `postgresql_installer.exe`, haciendo que el instalador pese aproximadamente 482 MB.

Quiero que el instalador estándar de Kairo sea liviano, aproximadamente 125 MB, y que PostgreSQL pase a ser una DEPENDENCIA DESCARGABLE bajo demanda.

La idea NO es crear una versión "sin PostgreSQL" de Kairo.

Es el mismo Kairo, misma versión, mismos canales y mismo updater.

La diferencia es únicamente cómo se obtiene PostgreSQL durante la instalación inicial.

# ARQUITECTURA DESEADA

El instalador estándar:

```text
KairoSetup.exe
    |
    |-- Kairo frontend/backend
    |
    `-- PostgreSQL NO embebido
```

Cuando el instalador se ejecuta:

```text
                    KairoSetup.exe
                          |
                          v
                   Installer Wizard
                          |
                          v
                 ¿Modo Cliente?
                    /         \
                  SÍ           NO
                  |             |
                  v             v
          PostgreSQL no    ¿PostgreSQL
             necesario      detectado?
                              /    \
                            SÍ      NO
                            |        |
                            v        v
                       Detectar    Ofrecer
                       instancia   descarga
                            |        |
                            |        v
                            |    GitHub Dependency
                            |        |
                            |        v
                            |    SHA-256 verify
                            |        |
                            |        v
                            |    Instalar PG
                            |        |
                            +----+---+
                                 |
                                 v
                         Configuración DB
                                 |
                    +------------+------------+
                    |                         |
                    v                         v
             Probar conexión              Error
                    |                         |
                   OK                         |
                    |                         |
                    +------------+------------+
                                 |
                                 v
                         Configurar Kairo
                                 |
                                 v
                         Instalar / finalizar
```

# REGLA FUNDAMENTAL

PostgreSQL NO debe formar parte del `.exe` estándar.

No quiero:

```text
KairoSetup.exe
  └── PostgreSQL 357 MB
```

Quiero:

```text
KairoSetup.exe
  └── Kairo solamente
```

y PostgreSQL como dependencia externa descargable.

# GITHUB / DEPENDENCIA

No quiero subir los aproximadamente 357 MB de PostgreSQL en cada release de Kairo.

Crear una estrategia de dependencia separada, por ejemplo:

```text
Kairo Dependencies
    PostgreSQL 17.x
        postgresql_installer.exe
        SHA256
```

La versión de PostgreSQL debe estar FIJADA.

NO utilizar "latest PostgreSQL" dinámicamente.

El instalador debe conocer:

- URL de descarga
- versión esperada
- SHA-256 esperado

La URL y SHA-256 deberían poder configurarse mediante defines/parámetros del build para que `publish.bat` no requiera modificar manualmente el `.iss`.

Usar la capacidad nativa de descarga de Inno Setup si la implementación actual/version de Inno Setup lo soporta, incluyendo:

- progreso
- cancelación
- verificación SHA-256
- manejo de errores

NO agregar una solución externa si Inno Setup ya proporciona la funcionalidad necesaria.

# DETECCIÓN DE POSTGRESQL

Cuando el instalador necesite PostgreSQL debe intentar detectar una instalación existente.

La detección NO debe asumir simplemente:

```text
localhost:5432
```

Debe intentar determinar realmente:

- versión
- instalación
- ruta
- servicio
- puerto configurado
- estado del servicio

Debe soportar el caso de que existan varias versiones/instancias.

Por ejemplo:

```text
PostgreSQL 16
    puerto 5432

PostgreSQL 17
    puerto 5433
```

NO quiero que el instalador seleccione arbitrariamente una de ellas.

Debe mostrar claramente qué instancia encontró y permitir al usuario corregir los parámetros.

Ejemplo:

```text
PostgreSQL detectado

Versión: PostgreSQL 17
Ubicación: C:\Program Files\PostgreSQL\17
Servicio: postgresql-x64-17

Configuración de conexión:

Host:      localhost
Puerto:    5433
Usuario:   postgres
Contraseña: ********

[ Probar conexión ]
```

Los valores deben ser editables.

# VALIDACIÓN DE CONEXIÓN

Este punto es OBLIGATORIO.

No quiero que el instalador simplemente escriba `appsettings.json` y diga que terminó.

Antes de completar la configuración de base de datos debe existir una acción:

```text
[ Probar conexión ]
```

Debe comprobar realmente que:

- host responde
- puerto responde
- usuario existe
- contraseña es válida
- PostgreSQL acepta la conexión

Si la conexión falla:

```text
No se pudo conectar a PostgreSQL.

[detalle del error]

[ Volver y corregir ]
```

El usuario debe poder corregir:

- host
- puerto
- usuario
- contraseña

y volver a probar.

La contraseña NO debe exponerse en comandos de `cmd.exe`, argumentos visibles del proceso ni logs.

Usar un mecanismo seguro para proporcionar la credencial al proceso de validación.

# POSTGRESQL NO INSTALADO

Si el instalador no encuentra PostgreSQL:

Mostrar algo similar a:

```text
PostgreSQL no detectado

Kairo necesita PostgreSQL para este tipo de instalación.

Puedes descargar e instalar PostgreSQL automáticamente.

Tamaño aproximado: 357 MB

[ Descargar e instalar ]

[ Continuar sin PostgreSQL ]
```

Si el usuario selecciona:

```text
Continuar sin PostgreSQL
```

NO bloquear toda la instalación.

Debe:

1. mostrar una advertencia clara;
2. permitir continuar;
3. dejar claro que Kairo no podrá utilizar la base local hasta configurarla;
4. no dejar la impresión de que PostgreSQL fue instalado correctamente.

Esto corresponde al escenario que quiero soportar.

# SI POSTGRESQL SÍ EXISTE

Si PostgreSQL ya está instalado:

NO descargarlo.

NO reinstalarlo.

NO sobrescribir innecesariamente la instalación existente.

Mostrar la instancia detectada y pedir/configurar:

```text
Host
Puerto
Usuario
Contraseña
```

y validar la conexión antes de continuar.

Si posteriormente Kairo necesita modificar la contraseña del usuario de aplicación (`kairo_user`) mediante el superusuario, conservar el comportamiento actual, pero utilizar las credenciales reales proporcionadas por el usuario.

NO generar una contraseña ficticia para `postgres`.

# INSTALACIÓN AUTOMÁTICA DE POSTGRESQL

Cuando el usuario decide descargar PostgreSQL:

1. descargar el installer desde la URL configurada;
2. verificar SHA-256;
3. mostrar progreso;
4. permitir cancelación;
5. ejecutar la instalación actual de PostgreSQL utilizando el flujo que ya existe;
6. respetar la configuración de usuario/contraseña que corresponda;
7. detectar posteriormente la instancia instalada;
8. obtener/confirmar el puerto;
9. probar conexión;
10. continuar con la configuración actual de Kairo.

Quiero reutilizar la lógica existente siempre que sea posible.

NO dupliques innecesariamente la lógica actual de instalación/configuración.

# APPSETTINGS

Mantener el comportamiento actual respecto a:

```text
{app}\api\appsettings.json
```

Primero verifica exactamente cómo funciona actualmente:

- `[Files]`
- `onlyifdoesntexist`
- `WriteAppSettings()`
- `ssPostInstall`
- modos Cliente / Servidor / Standalone

NO cambies este comportamiento sin necesidad.

La nueva arquitectura debe integrarse con él.

La configuración final de PostgreSQL debe terminar correctamente reflejada en `appsettings.json`.

# UPDATER

ESTO ES CRÍTICO.

Las actualizaciones automáticas de Kairo NO deben cambiar.

El updater debe continuar descargando únicamente los artefactos actuales:

```text
frontend.zip
backend.zip
```

PostgreSQL NO debe formar parte de las actualizaciones normales de Kairo.

Una instalación realizada con:

```text
KairoSetup.exe
```

debe actualizarse exactamente igual que una instalación anterior.

NO crear:

```text
alpha-nopg
beta-nopg
stable-nopg
```

NO duplicar versiones.

NO duplicar canales.

El instalador liviano es solamente un "sabor de empaquetado", no una versión diferente de Kairo.

# BUILD / PUBLISH.BAT

Modificar `publish.bat`.

Después de seleccionar el canal, quiero poder elegir entre:

```text
1. Build installer
2. Build installer and publish to GitHub
3. Build offline installer with bundled PostgreSQL
4. Build offline installer and publish to GitHub
```

Puedes ajustar los nombres si la estructura actual del menú requiere algo mejor.

El comportamiento deseado es:

## Build estándar

```text
KairoSetup.exe
```

NO contiene PostgreSQL.

## Build offline/bundled

```text
KairoSetup-Offline.exe
```

SÍ contiene PostgreSQL.

Este segundo instalador existe específicamente para instalaciones sin Internet.

No quiero que el build offline cambie la versión de Kairo.

# INNO SETUP

Utilizar compilación condicional/preprocesador para que PostgreSQL solamente se incluya cuando se solicite el build bundled/offline.

Conceptualmente:

```pascal
#ifdef BundlePostgres

  Source: "assets\postgresql_installer.exe";
  ...

#endif
```

El build estándar debe poder compilarse sin que `postgresql_installer.exe` exista localmente.

Esto es importante para CI/builds limpios.

El instalador estándar NO debe contener accidentalmente el archivo.

# NOMBRES DE ASSETS

Evitar que builds distintos se sobrescriban.

Por ejemplo:

```text
KairoSetup.exe
KairoSetup-Offline.exe
```

Pero conserva la convención actual del proyecto si ya existe una mejor.

# MANIFEST

Revisar cómo se genera actualmente el manifiesto.

El asset del installer debe apuntar al instalador correspondiente.

El updater NO debe tratar PostgreSQL como un archivo actualizable.

No introducir PostgreSQL en:

```text
frontend.zip
backend.zip
```

ni en ningún otro artefacto de actualización.

# SEGURIDAD

La contraseña de PostgreSQL:

- no debe aparecer en logs;
- no debe aparecer en argumentos de procesos;
- no debe guardarse en archivos temporales innecesarios;
- debe manejarse de forma segura durante la validación/configuración.

La URL de descarga de PostgreSQL debe estar acompañada por SHA-256.

Si el hash no coincide:

```text
NO ejecutar el instalador descargado.
```

Mostrar un error claro y detener esa parte del proceso.

# COMPATIBILIDAD

Antes de modificar código, identifica:

1. cómo se detecta actualmente PostgreSQL;
2. cómo se obtiene la ruta;
3. cómo se obtiene el puerto;
4. cómo se ejecuta actualmente `postgresql_installer.exe`;
5. cómo se configura PostgreSQL;
6. cómo se genera `appsettings.json`;
7. cómo funciona `publish.bat`;
8. cómo se genera el manifest;
9. cómo funciona el updater;
10. qué partes ya existen y pueden reutilizarse.

NO reescribas componentes que ya funcionan correctamente.

# TESTS

Agregar/actualizar pruebas para verificar como mínimo:

### Build estándar

```text
KairoSetup.exe
```

NO contiene:

```text
postgresql_installer.exe
```

ni los ~357 MB asociados.

### Build offline

```text
KairoSetup-Offline.exe
```

SÍ contiene PostgreSQL.

### Instalación con PostgreSQL existente

Debe:

```text
detectar
→ mostrar
→ permitir editar
→ probar conexión
→ configurar Kairo
```

### Instalación sin PostgreSQL

Debe:

```text
detectar ausencia
→ ofrecer descarga
→ permitir cancelar
→ avisar
→ permitir continuar
```

### Instalación descargando PostgreSQL

Debe:

```text
download
→ SHA256
→ install
→ detect
→ configure
→ test connection
```

### Updater

Verificar que:

```text
frontend.zip
backend.zip
```

continúan funcionando independientemente de cómo se instaló PostgreSQL.

# REGLA DE IMPLEMENTACIÓN

Quiero que primero hagas una auditoría del código existente y me presentes:

1. archivos que vas a modificar;
2. archivos que vas a crear;
3. flujo actual;
4. flujo nuevo;
5. posibles riesgos;
6. cómo vas a mantener compatibilidad con el updater.

Después implementa.

No quiero una solución conceptual desconectada del código existente.

Quiero una implementación integrada con la arquitectura actual de Kairo y reutilizando todo lo que ya funciona.

El resultado final debe ser:

```text
                    KAIRO INSTALLER

                         │
                         ▼
                 Instalador ~125 MB
                         │
                         ▼
              ¿Necesita PostgreSQL?
                    /          \
                  NO            SÍ
                  │              │
                  │        ¿Ya existe?
                  │          /       \
                  │        SÍ         NO
                  │        │           │
                  │        │      Descargar
                  │        │      desde GitHub
                  │        │           │
                  │        │        SHA-256
                  │        │           │
                  │        └─────┬─────┘
                  │              │
                  │              ▼
                  │       Configurar DB
                  │              │
                  │              ▼
                  │       Probar conexión
                  │              │
                  └──────────────┤
                                 ▼
                         Configurar Kairo
                                 │
                                 ▼
                           Instalación
                                 │
                                 ▼
                              Updater
                                 │
                         ┌───────┴───────┐
                         ▼               ▼
                    frontend.zip   backend.zip

                    PostgreSQL queda
                    fuera del updater.
```

La prioridad es que el resultado sea **realmente funcional**, no solamente que el `.exe` pese menos.

Una última recomendación

Hay una decisión que me parece especialmente buena en lo que estás planteando: mantener el instalador offline.

Así terminas con:

Instalador Tamaño Internet PostgreSQL
KairoSetup.exe ~125 MB Para descargar PG si hace falta Bajo demanda
KairoSetup-Offline.exe ~482 MB No necesario Embebido

Eso te da un instalador moderno para la mayoría de los casos y, al mismo tiempo, una salida para técnicos que instalan Kairo en PCs sin Internet.

Y lo mejor: ambos terminan produciendo exactamente la misma instalación de Kairo y utilizan exactamente el mismo sistema de actualizaciones.

---

Auditoría completa. Primero lo que preguntaste, que es lo único que te bloquea a vos.

Cómo subir PostgreSQL y qué URL necesito
Sí, subilo igual que un release, pero a un release aparte y de larga vida, no atado a una versión de Kairo:

gh release create deps-postgresql-17 \
 "installer/assets/postgresql_installer.exe" \
 --title "Dependencias: PostgreSQL 17" \
 --notes "Instalador de PostgreSQL 17 usado por KairoSetup.exe bajo demanda. No es una versión de Kairo." \
 --latest=false
El --latest=false importa: sin él, GitHub lo marca como "Latest release" y quien busque Kairo se encuentra con PostgreSQL.

La URL que queda, y la que necesito, es:

https://github.com/esbanegas/kairo-desktop/releases/download/deps-postgresql-17/postgresql_installer.exe
No necesito nada más de vos — ya calculé el resto del archivo que tenés local:

Tamaño : 373,830,744 bytes (356.5 MB)
Versión : PostgreSQL 17
SHA-256 : c0728faccc95ced5a280efdc32413fe35764b2302670eec72569b0fd41ac3513
Ese hash queda fijado como define en el build. Si el archivo que subís no es exactamente este, decímelo y lo recalculo.

Auditoría y plan

1. Flujo actual (verificado en código)
   Pieza Cómo está hoy
   Detección PG IsPostgresInstalled lee solo Version del registro. No lee Location, ni servicio, ni puerto
   Puerto Hardcodeado 5432 en WriteAppSettings (modo automático). Editable solo en modo personalizado
   Ejecución PG ssPostInstall → InstallPostgresElevated → ShellExec('runas', ...) con --mode unattended --disable-components stackbuilder --superpassword
   Config WriteAppSettings escribe {app}\api\appsettings.json; el backend reconcilia con ALTER ROLE al arrancar
   Validación Solo campos no vacíos. Cero prueba de conexión
   Updater Ignora la entrada installer del manifiesto; baja solo frontend.zip/backend.zip
   Lo que ya existe y pienso reutilizar tal cual: los campos editables de la página personalizada (PgHost/PgPort/PgAdminUser/PgAdminPass/PgDbName/PgAppUser), GetPostgresInstallerParams, WriteAppSettings, RunElevatedPhase y todo el [Files].

2. Flujo nuevo y el cambio estructural que implica
   Hay un punto que quiero que veas antes de aprobar, porque es el de más riesgo:

Hoy PostgreSQL se instala en ssPostInstall, o sea al final, después del asistente. Pero pediste "Probar conexión" con opción de "Volver y corregir". Eso solo es posible dentro del asistente. Así que la instalación de PostgreSQL tiene que moverse de ssPostInstall al asistente.

Orden nuevo:

Página Modo → (si no es Cliente) → Página BD
├─ PG detectado: muestra versión/ruta/servicio/puerto
│ campos editables + [Probar conexión]
└─ PG ausente: [Descargar e instalar] o [Continuar sin PostgreSQL]
↓ descarga + SHA-256 + instala + re-detecta
→ [Probar conexión] → OK → wpReady → copia archivos
→ ssPostInstall: WriteAppSettings + firewall
WriteAppSettings, [Files] y el ssPostInstall quedan intactos. Lo único que se mueve es la instalación de PostgreSQL; el firewall se queda donde está.

3. Archivos
   Modifico: enlip_setup.iss (el grueso), publish.bat (menú + /DBundlePostgres + nombres de asset), test-install-model.ps1 (aserciones nuevas), RELEASE_GUIDE.md.

Creo: nada. Los defines de URL/SHA/versión van por línea de comandos desde publish.bat.

4. Riesgos, y uno sale de tu captura
   psql.exe puede no existir. Tu imagen muestra justo el problema: el instalador de EDB tiene Command Line Tools como componente desmarcable. Tu instalación desatendida usa --disable-components stackbuilder, así que sí instala las herramientas de línea de comandos y psql.exe queda en {Location}\bin. Pero un PostgreSQL preexistente que alguien instaló a mano puede no tenerlo.

Mi decisión: si falta psql.exe, no bloqueo — aviso que no se pudo verificar y dejo continuar. Bloquear por una herramienta ausente sería peor que el problema.

Otros:

Los assets de GitHub redirigen a release-assets.githubusercontent.com. DownloadTemporaryFile sigue redirecciones, pero lo verifico contra la URL real antes de dar nada por hecho.
Múltiples instancias (tu máquina tiene 16 y 17 corriendo): detecto y muestro lo encontrado, con los campos editables. No elijo por el usuario.
Volver atrás en el asistente tras instalar PostgreSQL: guardo un flag para no reinstalarlo.
El build estándar debe compilar sin el archivo de 357 MB presente (ya está en .gitignore). 5. Compatibilidad con el updater
Cero cambios. Verificado por código: if (key === "installer" || !file?.name) continue;. El updater nunca toca esa entrada. frontend.zip y backend.zip son byte a byte idénticos en ambos sabores. Sin canales nuevos, sin versiones duplicadas.

Una instalación hecha con el liviano y otra con el offline se actualizan exactamente igual.

6. Lo que NO voy a tocar
   Tu restricción es la que manda: el instalador funciona hoy. No reescribo la detección de modo (Standalone/Servidor/Cliente), ni las páginas existentes, ni WriteAppSettings, ni [Files], ni el [Run], ni nada del updater. Agrego detección real, la prueba de conexión, la descarga bajo demanda y el #ifdef.

Tal como pide tu documento, no toqué código todavía. Dos cosas y arranco:

Subí el release de dependencias y confirmame que la URL quedó como la de arriba (o pasame la que haya quedado).
¿Te sirve el orden nuevo de mover la instalación de PostgreSQL al asistente? Es lo único que altera el flujo actual, y es inevitable si querés "Probar conexión" con "Volver y corregir".

Sí, aprobado el enfoque.

Subiré el release de dependencias con PostgreSQL 17 usando el archivo que ya verificaste:

URL esperada:
https://github.com/esbanegas/kairo-desktop/releases/download/deps-postgresql-17/postgresql_installer.exe

SHA-256:
c0728faccc95ced5a280efdc32413fe35764b2302670eec72569b0fd41ac3513

Y sí, me sirve el nuevo orden de mover la instalación de PostgreSQL al asistente, porque quiero que la validación de conexión ocurra antes de finalizar y que el usuario pueda volver y corregir host, puerto, usuario o contraseña.

Solo agrega esta condición importante a la implementación:

Quiero que la lógica de instalación de PostgreSQL quede encapsulada/reutilizable y no acoplada únicamente al nuevo flujo online.

Debe soportar exactamente estos escenarios:

1. PostgreSQL ya existe:
   - Detectarlo.
   - Mostrar versión, ruta, servicio y puerto cuando sea posible.
   - Permitir editar host/puerto/usuario/contraseña.
   - Probar conexión.
   - NO reinstalar PostgreSQL.

2. PostgreSQL no existe + instalador estándar:
   - Mostrar que no está instalado.
   - Ofrecer descargarlo desde GitHub.
   - Verificar SHA-256.
   - Instalarlo.
   - Volver a detectar la instancia.
   - Configurar y probar conexión.

3. PostgreSQL no existe + usuario decide no descargar:
   - Mostrar advertencia clara.
   - Permitir continuar.
   - No fingir que la base está configurada.

4. Instalador Offline/Bundled:
   - PostgreSQL debe venir embebido.
   - No debe necesitar Internet.
   - Utilizar la misma lógica de instalación/configuración.
   - La diferencia debe ser únicamente el origen del instalador de PostgreSQL.

Es decir:

Online:
KairoSetup → detectar → descargar PG si hace falta → instalar → configurar → probar

Offline:
KairoSetup-Offline → detectar → usar PG embebido si hace falta → instalar → configurar → probar

Y en ambos casos el resultado debe ser la misma instalación de Kairo.

También mantén exactamente la decisión anterior de no tocar el updater: PostgreSQL no participa en las actualizaciones normales de Kairo.

Con eso, dale adelante con la implementación completa.

Antes de modificar cada archivo, conserva la auditoría que acabas de hacer como guía y evita reescribir componentes existentes que ya funcionan.
