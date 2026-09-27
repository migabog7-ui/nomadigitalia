[README.md](https://github.com/user-attachments/files/32691532/README.md)
# NŌMA — configuração real do Supabase

Este projeto passou de ficheiros HTML soltos para um pequeno projeto **Vite**, precisamente para poder usar variáveis de ambiente (`import.meta.env`) — isso não existe em HTML puro sem um passo de build. A app inteira mantém-se a mesma (mesmo design, mesma lógica); só a forma de configurar a ligação ao Supabase mudou.

## C) Onde encontro o SUPABASE URL / D) a ANON KEY

No teu projeto Supabase: **Project Settings → API**.
- **Project URL** → isto é o `VITE_SUPABASE_URL`
- **anon public** (na secção "Project API keys") → isto é o `VITE_SUPABASE_ANON_KEY`

Não uses a `service_role key` em lado nenhum deste projeto — essa nunca deve sair do backend, e este projeto não tem backend próprio (fala diretamente com o Supabase a partir do browser, protegido pelas políticas RLS).

## E) O que tens de colocar no Supabase

Se ainda não o fizeste (segue o `supabase/schema.sql`):
1. SQL Editor → corre `supabase/schema.sql` completo. Cria as tabelas, o RLS, e semeia o restaurante NŌMA com categorias/produtos/mesas.
2. Authentication → Users → cria o teu utilizador admin (email + password).
3. Copia o UUID desse utilizador e corre no SQL Editor:
   ```sql
   insert into restaurant_staff (user_id, restaurant_id)
   select 'COLA-AQUI-O-UUID', id from restaurants where slug='noma';
   ```

## B) Variáveis de ambiente a criar

```
VITE_SUPABASE_URL=https://xxxxxxxx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJ...
```
O prefixo `VITE_` é obrigatório — só variáveis com esse prefixo ficam acessíveis no código do browser; é assim que o Vite as distingue de segredos de servidor.

## G) Como executar localmente

```bash
npm install
cp .env.example .env
# abre .env e cola os dois valores (C e D acima)
npm run dev
```
Abre o URL que aparece no terminal (normalmente `http://localhost:5173`).
- Página inicial (`/`) — testa a ligação e mostra "Ligado" ou o erro exato.
- Cliente: `/menu.html?table=1`
- Admin: `/admin.html`

Sempre que mudares o `.env`, tens de reiniciar `npm run dev` — o Vite só lê estas variáveis no arranque.

## F) Como testar a ligação

Três formas, da mais simples à mais detalhada:
1. Abre `/` — o indicador mostra "Ligado" a verde ou o erro a vermelho.
2. Abre `/menu.html?table=1` ou `/admin.html` diretamente — se algo estiver mal, aparece um ecrã claro a dizer que falta configuração ou que a ligação falhou, nunca um ecrã em branco.
3. Consola do browser (F12) — qualquer erro do Supabase aparece aí com detalhe.

## H) Preparar para o Vercel

1. Sobe este projeto para um repositório GitHub (o `.gitignore` já impede o `.env` de ir junto).
2. [vercel.com](https://vercel.com) → **New Project** → importa o repositório. O Vercel deteta Vite automaticamente.
3. Antes do primeiro deploy (ou depois, em **Settings → Environment Variables**): adiciona `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` com os mesmos valores do teu `.env`.
4. Deploy. Os teus links ficam `https://o-teu-projeto.vercel.app/menu.html?table=1` e `.../admin.html`.
5. Nas Mesas do Admin, o botão "Ver QR Code" já usa o domínio onde a app está a correr — não precisas de mudar nada no código ao passar de localhost para Vercel.

---

## A) Ficheiros alterados

Reestruturação completa para suportar variáveis de ambiente:
- **Novo:** `package.json`, `vite.config.js`, `.env.example`, `.gitignore` — o esqueleto do projeto Vite.
- **Novo:** `src/supabase-client.js` — a mesma camada de dados de antes, agora um módulo ES que lê `import.meta.env.VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` em vez de duas strings escritas no código. Exporta também `isConfigured` e `testConnection()`.
- **Novo:** `src/menu.js`, `src/admin.js` — a lógica que antes estava dentro de `<script>` em `menu.html`/`admin.html`, agora como módulos que importam de `supabase-client.js`. Comportamento idêntico, mais os ecrãs de "não configurado" / "falha na ligação".
- **Alterado:** `menu.html`, `admin.html` — o mesmo desenho visual (CSS igual), mas mais curtos: já não têm o código embutido, só carregam o módulo correspondente.
- **Novo:** `index.html` — página de diagnóstico com o teste de ligação e atalhos para o Cliente/Admin.
- **Sem alterações:** `supabase/schema.sql` — a estrutura da base de dados é a mesma de antes.

## Segurança — o que já está garantido

- A anon key fica no `.env` (nunca no código) e sai apenas para o browser da mesma forma que já sairia de qualquer app pública — é uma chave pública por desenho, protegida pelas políticas RLS que já correram no schema, não por estar escondida.
- `service_role key`: nunca é referida em nenhum ficheiro deste projeto.
- `.env` está no `.gitignore` — não vai para o GitHub. Só o `.env.example` (vazio) é commitado.
- RLS mantém-se ativo em todas as tabelas: um visitante anónimo só lê menu ativo/disponível e só pode criar pedidos; só quem está em `restaurant_staff` altera produtos, categorias, mesas ou o estado de um pedido.

## O que continua por confirmar

Continuo sem acesso à internet neste ambiente, por isso nada disto foi corrido contra um Supabase real. A mudança mais delicada é a exposição de funções em `window` no fim de `menu.js`/`admin.js` — necessária porque os módulos ES não expõem automaticamente as suas funções ao HTML gerado dinamicamente (o `onclick="..."` só funciona se a função existir em `window`). Se, depois de `npm run dev`, algum botão não reagir ao clique, é o primeiro sítio a verificar — diz-me o erro exato da consola (F12) e corrijo.
