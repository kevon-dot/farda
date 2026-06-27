const config = require('../config/config');



const verifyDeviceAuth = async (req, res, next) => {
    try {
    const apiKey = req.headers['x-api-key'];
    
    if (!apiKey) {
      return res.status(401).json({
        success: false,
        error: 'API key required. Include X-API-Key header'
      });
    }

    if (apiKey !== config.device.apiKey) {
      return res.status(401).json({
        success: false,
        error: 'Invalid API key'
      });
    }

    next();
    
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: 'Authentication error'
    });
  }
}

module.exports = verifyDeviceAuth;