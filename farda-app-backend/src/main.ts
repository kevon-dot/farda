import logger from "jet-logger";
import env from "./common/constants/env";
import server from "./server";

/******************************************************************************
                                Constants
******************************************************************************/

const SERVER_START_MESSAGE = `Express server started on ${env.HOST}:${env.PORT}`;

/******************************************************************************
                                  Run
******************************************************************************/

// Start the server
server.listen(env.PORT, env.HOST, (err) => {
	if (err) {
		logger.err(err.message);
	} else {
		logger.info(SERVER_START_MESSAGE);
	}
});
