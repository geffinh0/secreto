# ENGENHARIA REVERSA: AUTENTICAÇÃO E SESSÃO

Este documento detalha o mecanismo de autenticação, cabeçalhos e ciclo de vida da sessão no SuperLive.

---

## 1. Headers de Autenticação (`HeaderInterceptor.java`)

Todas as requisições autenticadas devem incluir:

```http
Authorization: Token <token_de_acesso_do_usuario>
Device-ID: <uuid_v4_do_dispositivo>
User-Agent: SuperLive/2.31.0 (samsung SM-G998B; Android 13; Scale/3.0)
Content-Type: application/json; charset=UTF-8
Accept: application/json
```

### Detalhes Importantes:
1. O prefixo no header de autorização é a palavra literal `Token ` seguida pelo hash hexadecimal de 40 a 64 caracteres do token gerado no login (e não `Bearer`).
2. O `Device-ID` é gerado na primeira inicialização (`UUID.randomUUID().toString()`) e persistido localmente.

---

## 2. Métodos de Login e Cadastro

### 2.1. Email e Senha
- **Endpoint:** `POST user/signup/email_signin`
- **Payload:** `{"email": "...", "password": "..."}`
- **Retorno:** Objeto com `token`, `user_id` e dados de perfil inicial.

### 2.2. Login com Telefone / SMS
- **Etapa 1:** `POST user/signup/send_phone_verification_code` com `{"phone_number": "+5511999999999"}`
- **Etapa 2:** `POST user/signup/auth_phone` com `{"phone_number": "+5511999999999", "code": "123456"}`

### 2.3. Login Social (Google / Apple / Twitter)
- O aplicativo cliente obtém o token de identidade (ID Token) do provedor nativo e envia para `POST user/signup/google` ou `POST user/signup/twitter`.

---

## 3. Gestão e Validação da Sessão

- O estado da sessão é consultado chamando `POST users/own_profile`.
- Caso o servidor retorne código HTTP `401 Unauthorized` ou código de erro de sessão expirada no corpo JSON, o cliente limpa as credenciais salvas e redireciona para a tela de login.
- O logout explícito é realizado via `POST user/logout`, que invalida o token no servidor e limpa a sessão.
