const express = require('express');
const app = express();

// Direct route calls (EXPR-01)
app.get('/api/users', listUsers);
app.post('/api/users', createUser);
app.put('/api/users/:userId', updateUser);
app.delete('/api/users/:userId', deleteUser);
app.patch('/api/users/:userId', patchUser);
app.options('/api/users', optionsUsers);
app.head('/api/users', headUsers);

// app.all (EXPR-02)
app.all('/api/health', healthCheck);

// Path params (EXPR-04) — :param and *wildcard
app.get('/api/files/*filepath', serveFile);
app.get('/api/teams/:teamId/members/:memberId', getTeamMember);

// app.route() chaining (EXPR-03)
app.route('/api/posts/:postId')
  .get(getPost)
  .post(createPost)
  .delete(deletePost);

// Middleware that should be EXCLUDED (EXPR-05)
app.use(express.json());
app.use('/api', apiRouter);
app.use((req, res, next) => { next(); });

// Inline handlers (arrow functions) — func should be ""
app.get('/api/inline', (req, res) => { res.json({ ok: true }); });

app.listen(3000);
