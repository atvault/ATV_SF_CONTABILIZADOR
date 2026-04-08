# ATV SF Contabilizador

Proyecto **Salesforce DX** (API 61) con reportes operativos en **Apex** y **Lightning Web Components (LWC)** para contabilizar actividades comerciales y métricas por cuenta/candidato en el contexto Castle / AT Vault.

## Requisitos

- **Salesforce CLI** (`sf`) autenticado contra la org destino.
- Campos y objetos usados por los reportes (entre otros):
  - **Contact.Candidato__c** — lookup al Lead candidato (usado en reportes de actividades y contexto de “candidato”).
  - Historial de etapas de oportunidad donde aplique el reporte Sondeo (`OpportunityHistory`).

## Estructura del repositorio

| Ruta | Descripción |
|------|-------------|
| `force-app/main/default/` | Metadatos desplegables: Apex, LWC, permission sets. |
| `docs/` | Documentación adicional (p. ej. instrucciones de despliegue por módulo). |
| `manifest/` | Manifiestos XML para retrieve/deploy selectivo. |
| `retrieve-prod-check/` | Referencias de metadatos recuperados para comprobaciones (p. ej. campo `Candidato__c`). |
| `sfdx-project.json` | Configuración del paquete por defecto (`force-app`). |
| `.gitignore` | Evita subir secretos, caché de CLI (`.sfdx/`, `.sf/`), `.env`, certificados y volcados locales (p. ej. `orglist.json`). |

### Secretos y repositorio

- **`.gitignore`** marca qué no debe versionarse; Git **no** “des-commitea” solo: si algo sensible ya entró al repo, ejecutá `git rm --cached <ruta>` y un commit nuevo (y si hubo push a un remoto, **revocá tokens** en Salesforce y considerá `git filter-repo` / soporte del hosting para limpiar historial).
- No guardes **access tokens**, contraseñas ni `orglist.json` exportados de la CLI en el proyecto.

---

## Módulo 1 — Reporte de actividades (leads / candidatos)

**Objetivo:** agregar **eventos** y **tareas** por **propietario**, distinguiendo actividades cuyo **Who** es un **Lead** y actividades cuyo **Who** es un **Contact** con candidato informado (`Candidato__c`).

| Pieza | Rol |
|-------|-----|
| `classes/CastleLeadActivityReportSvc.cls` | Lógica SOQL: agregados `COUNT` por `OwnerId`, semi-joins a Lead y a Contact con `Candidato__c`, cálculo de **WhoId distintos** en Apex (no se usa `COUNT_DISTINCT` sobre `WhoId` polimórfico en agregados), enriquecimiento de email del usuario propietario. Validación de permisos de lectura. |
| `classes/CastleLeadActivityReportSvcTest.cls` | Pruebas unitarias del servicio. |
| `classes/CastleEventsCandidateReportController.cls` | Capa `@AuraEnabled` para LWC: mapea filtros y DTOs hacia/desde el servicio. |
| `classes/CastleEventsCandidateReportCtrlTest.cls` | Pruebas del controlador. |
| `lwc/castleEventsCandidateReport/` | UI: filtros (fechas, usuario), KPIs y tabla por propietario. |
| `permissionsets/Castle_Events_Candidate_Report.permissionset-meta.xml` | Permisos de lectura (Event, Task, Lead, Contact, `Candidato__c`) y acceso a clases Apex necesarias. |

**Despliegue / tests (ejemplo):** ver `docs/INSTRUCCIONES_CASTLE_EVENTOS_CANDIDATO.md` y usar `RunSpecifiedTests` con `CastleLeadActivityReportSvcTest` y `CastleEventsCandidateReportCtrlTest`.

---

## Módulo 2 — Reporte por cuenta (Sondeo)

**Objetivo:** métricas **por cuenta** (no por oportunidad): promedios de actividades, tiempo en etapa **“En Sondeo”** y acciones previas a entrar en esa etapa, usando **OpportunityHistory** y actividades (Task/Event) ligadas a oportunidades/cuentas según la lógica del servicio.

| Pieza | Rol |
|-------|-----|
| `classes/CastleAccountSondeoReportSvc.cls` | Consultas y cálculos del reporte (filtros por fechas/cuenta, métricas globales y por fila de cuenta). |
| `classes/CastleAccountSondeoReportSvcTest.cls` | Pruebas unitarias del servicio. |
| `classes/CastleAccountSondeoReportController.cls` | Exposición a LWC / Aura con DTOs y comprobación de permisos de lectura. |
| `classes/CastleAccountSondeoReportCtrlTest.cls` | Pruebas del controlador. |
| `lwc/castleAccountSondeoReport/` | UI: filtros, KPIs y tabla por cuenta. |
| `permissionsets/Castle_Account_Sondeo_Report.permissionset-meta.xml` | Permisos para objetos y campos requeridos por el reporte. |

La etapa configurable se alinea con el **StageName** real en la org (constante `STAGE_EN_SONDEO` en código).

---

## Comandos útiles

```bash
# Validar o desplegar (ajustar -o al alias de la org)
sf project deploy start -o <alias-org> --source-dir force-app --dry-run

# Ejemplo con tests específicos de un módulo (producción suele exigir tests)
sf project deploy start -o <alias-org> --source-dir force-app --test-level RunSpecifiedTests --tests CastleLeadActivityReportSvcTest --tests CastleEventsCandidateReportCtrlTest
```

Tras desplegar, asignar los **permission sets** correspondientes a los usuarios que deben ver cada LWC y colocar los componentes en **Lightning App Builder** (páginas de aplicación, inicio o pestañas según política de la org).

---

## Notas

- El nombre del proyecto en `sfdx-project.json` aparece como `castle-events-candidate-report`; el repositorio se usa como **contenedor** de varios reportes Castle (actividades + Sondeo).
- Si los filtros por fecha en el reporte de actividades fallan en una org concreta, revisar el mensaje de error en la UI o en logs: pueden aplicar límites de SOQL o restricciones según edición y datos.
