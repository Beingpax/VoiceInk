const express = require('express');
const cors = require('cors');
const authRoutes = require('./routes/auth');
const subscriptionRoutes = require('./routes/subscription');

const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

app.use('/auth', authRoutes);
app.use('/subscription', subscriptionRoutes);

app.listen(port, () => {
  console.log(`Server listening at http://localhost:${port}`);
});
