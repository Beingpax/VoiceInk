const express = require('express');
const jwt = require('jsonwebtoken');

const router = express.Router();
const subscriptions = {};
const JWT_SECRET = 'your-jwt-secret';

const verifyToken = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (token) {
    jwt.verify(token, JWT_SECRET, (err, user) => {
      if (err) {
        return res.sendStatus(403);
      }
      req.user = user;
      next();
    });
  } else {
    res.sendStatus(401);
  }
};

router.get('/status', verifyToken, (req, res) => {
  const user = req.user;
  const subscription = subscriptions[user.email];
  if (subscription) {
    res.json(subscription);
  } else {
    res.json({ status: 'inactive' });
  }
});

router.post('/subscribe', verifyToken, (req, res) => {
  const user = req.user;
  subscriptions[user.email] = { status: 'active', plan: 'premium' };
  res.send('Subscribed successfully');
});

module.exports = router;
