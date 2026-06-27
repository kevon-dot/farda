import type { Request, Response } from "express";

/******************************************************************************
                                Types
******************************************************************************/

type UrlParams = Record<string, string>;
type PlainObject = Record<string, unknown>;

export type Req = Request<UrlParams, void, PlainObject>;
export type Res = Response;
