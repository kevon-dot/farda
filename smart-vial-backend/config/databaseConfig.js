const mongoose = require('mongoose');
const config = require('./config');


const connectDB = async () => {
    try{
        const connect = await mongoose.connect(config.mongoUri.uri, {
            useNewUrlParser: true,
            useUnifiedTopology: true
        });
        console.log(`MongoDB connected: ${connect.connection.host}`);

        mongoose.connection.on('error', err => {
            console.error(`MongoDB connection error: ${err}`);
        });

        mongoose.connection.on('disconnected', () => {
            console.warn('MongoDB disconnected. Attempting to reconnect...');
            setTimeout(connectDB, 5000); 
        });

        process.on('SIGINT', async () => {
            await mongoose.connection.close();
            console.log('MongoDB connection closed due to app termination');
            process.exit(0);
        });
    }
    catch(err){
        console.error(`MongoDB connection error: ${err}`);
        setTimeout(connectDB, 5000); 
        process.exit(1);
    }
};

module.exports = connectDB;