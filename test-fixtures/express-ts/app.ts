import express, { Request, Response } from 'express';
const app = express();

// Direct route calls (ETS-01 — identical behavior to JS)
app.get('/api/users', listUsers);
app.post('/api/users', createUser);
app.put('/api/users/:userId', updateUser);
app.delete('/api/users/:userId', deleteUser);

// app.all (EXPR-02)
app.all('/api/health', healthCheck);

// Path params (EXPR-04)
app.get('/api/teams/:teamId/members/:memberId', getTeamMember);

// app.route() chaining (EXPR-03)
app.route('/api/posts/:postId')
  .get(getPost)
  .post(createPost);

// Middleware excluded (EXPR-05)
app.use(express.json());

// TypeScript-typed inline handler
app.get('/api/typed', (req: Request, res: Response) => { res.json({ ok: true }); });

app.listen(3000);
