require('dotenv').config()
const express = require('express');
const mongoose = require('mongoose');
const app = express();

app.use(express.json());

mongoose.connect(process.env.MONGO_URI)
    .then(() => console.log('MongoDB connected'))
    .catch(err => console.log('MongoDB connection error:', err));

// Routes
const ingestionRoutes = require('./routes/ingestionAPI');
app.use('/api/ingest', ingestionRoutes);

const caregiverRoutes = require('./routes/caregiverAPI');
app.use('/api/caregiver', caregiverRoutes);

const userRoutes = require('./routes/userAPI');
app.use('/api/user', userRoutes);

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`server running on port ${PORT}`));
