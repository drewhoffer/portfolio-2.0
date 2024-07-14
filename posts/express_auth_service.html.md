---
title: Express JWT Auth
date: 2023/09/27
description: Tutorial for building a ExpressJS microservice for authenticating users.
tags: web development, nodejs, express, auth, mongodb, jwt, docker, passwordless
author: Me
slug: express-jwt-auth
---


# Express JWT Auth Service

Auth was always something mysterious and difficult for me. I was always concerned that if I did it myself I would end up breaking something and have no way of knowing. To make matters worse there was never a clear video or guide showing how to actually implement it.

Once you get into the idea of authentication you are immediately greeted with the concepts of sessions, JWTs, cookies, bearer tokens, OAuth, etc. quite frankly it's very overwhealming if you are just getting into it and want a slower paced introduction. Maybe one day I will write an article explaining the differences but today I'd like to instead show you how to create an express backend authentication service.

## Overview

The app will:

- Authenticate users via magic email link (who needs passwords anyways)
- Issue JWT's to users upon clicking their magic link email
- Use the concept of "Access" and "Refresh" token's with an explanation of how they work
- Implement Clean architecture so that the service is easily testable
- Docker for running our database

## Prerequisites

- Node
- Docker
- Yarn or NPM
- A SendGrid account

## Getting up and running

Let's get started. Forgive me but to create a starting point there are going to be a few things we need to do. This will seem overwhelming at first but after we have this initial setup completed we can get into building the auth solution.

First things first, create a directory, in my case I am going to call it `auth-service`.

Next, run the command:

```sh
yarn init
```

(you can use NPM or Pnpm if you prefer. For this tutorial I will be using yarn) You should now have a directory with a `./package.json` file.

Now we will install the necessary packages to get us up and running. Run the command:

```sh
yarn add express jsonwebtoken cookie-parser cors cuid
```

Now to install some dev dependencies. Run the command:

```sh
yarn add -D @types/express @types/cookie-parser @types/cors @types/jsonwebtoken @types/cuid @types/node esbuild esbuild-register nodemon typescript env-cmd
```

This will install Typescript for our packages as well as give us the tools to use Typescript. Nodemon and esbuild will allow us to make changes to our files and have the server automatically updated with the changes. Finally, env-cmd will allow us to load in environment variables to our app.

Speaking of environment variables, we need to create a local file for holding those. I will call mine `.env.local` and put the following environment variables in it:

```
# Database
DB_URL=mongodb://root:example@localhost:27017/
DB_NAME=express-auth-service-example

# JWT secrets
REFRESH_TOKEN_SECRET=RefreshTokenSecretThatShouldBeChanged
ACCESS_TOKEN_SECRET=AccessTokenSecretThatShouldBeChanged
MAGIC_LINK_TOKEN_SECRET=MagicTokenSecretThatShouldBeChanged

# Redirect URLs
CLIENT_URL=http://localhost:3001
MAGIC_REDIRECT_URI=http://localhost:3000/v1/auth/magic

# Sendgrid Keys
SENDGRID_API_KEY=sg.something.somethingelse
SENDGRID_FROM_EMAIL=your_from_email@email.com

# CORS
BASE_DOMAIN=localhost

```

After creating a file for your environment variables, add the following script to your ```./package.json``` .

```json
"scripts": {
    "dev": "env-cmd -f .env.local nodemon --exec \"node -r esbuild-register ./src/index.ts\" -e .ts"
}
```

This will allow us to run `yarn dev` which will load the variables from `.env.local` into your app, run nodemon which will listen to changes to files, as well as esbuild-register which will load in your typescript configuration.

Let's create a Typescript configuration file. You can use your own or use this one.

`./tsconfig.json`

```json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "display": "Default",
  "compilerOptions": {
    "lib": ["ES2015"],
    "module": "CommonJS",
    "outDir": "./dist",
    "rootDir": ".",
    "composite": false,
    "declaration": true,
    "declarationMap": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "inlineSources": false,
    "isolatedModules": true,
    "moduleResolution": "node",
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "preserveWatchOutput": true,
    "skipLibCheck": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "useUnknownInCatchVariables": false
  },
  "exclude": ["node_modules"],
  "include": ["src/**/*"]
}
```

Next we are going to use docker and docker-compose to create a database for this app. You can use any database you would like but for this example we are going to use MongoDB. See the compose file below.

`./docker-compose.yml`

```yml
# Use root/example as user/password credentials
version: "3.1"

services:
  mongo:
    image: mongo
    restart: always
    ports:
      - 27017:27017
    environment:
      MONGO_INITDB_ROOT_USERNAME: root
      MONGO_INITDB_ROOT_PASSWORD: example

  mongo-express:
    image: mongo-express
    restart: always
    ports:
      - 8081:8081
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: root
      ME_CONFIG_MONGODB_ADMINPASSWORD: example
      ME_CONFIG_MONGODB_URL: mongodb://root:example@mongo:27017/
```

Make sure you have docker installed and run the command:

```sh
docker-compose up -d
```

To start the database.

Finally, let's create an entrypoint for our app. Create a `./src` directory and inside create both a `./src/index.ts` and `./src/server.ts`.

In `index.ts` paste the following code:

```ts
import { createServer } from "./server";

const port = process.env.PORT || 3000;
const server = createServer();

server.listen(port, () => {
  console.log(`api running on ${port}`);
});
```

Then we create our server. You'll notice that
`server.ts`

```ts
import { json, urlencoded } from "body-parser";
import express from "express";
import cors from "cors";
import cookieParser from "cookie-parser";

export const createServer = () => {
  const app = express();
  app
    .use(cookieParser())
    .use(
      cors({
        origin: [process.env.CLIENT_URL],
        allowedHeaders: ["Content-Type", "Authorization"],
        credentials: true,
      })
    )
    .use(
      urlencoded({
        extended: true,
      })
    )
    .use(json())
    .use("/v1", (_req, res) => {
      res.send("hello world!");
    })
    .all("*", (_req, res) => {
      res.sendStatus(403);
    });

  return app;
};
```

The above file creates an express json api with cookie-parser middleware setup, cors configured to allow for authorization headers (needed for allowing auth cookie headers), a endpoint labeled "v1" that we will be placing all of our endpoints into, and finally a catch-all route to sendback a 403 for users requesting a route that doesn't exist.

Phew, that was a lot but taking a look back we have done a lot of initial configuration. You might be wondering why we created both an `./src/index.ts` and a `./src/server.ts`. The reason is, when you want to test your server, you can import the `./src/server.ts` file and can start and stop it at your choosing (this is beneficial for testing).

## Express Adapter

```ts
import { Request } from "express";
import { Cookie } from "../tokenUtils";

export interface HttpRequest {
  path: string;
  method: any; //"GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  pathParams: any;
  queryParams: any;
  body: any;
  user?: HttpRequestUser;
  headers: any;
  files?: any[];
  cookies?: any;
}

export interface HttpRequestUser {
  id: string;
}

export interface HttpResponse {
  body?: any;
  statusCode: number;
  headers?: any;
  cookies?: Cookie[];
  redirectTo?: string;
}

export interface MakeHttpError {
  statusCode: number;
  errorMessage?: string;
}

export function adaptRequest(req: Request) {
  return Object.freeze({
    path: req.path,
    method: req.method,
    pathParams: req.params,
    queryParams: req.query,
    body: req.body,
    headers: req.headers,
    user: req.user as HttpRequestUser,
    cookies: req.cookies,
  });
}

export default function makeHttpError({
  statusCode,
  errorMessage,
}: MakeHttpError) {
  return {
    statusCode,
    data: {
      error: errorMessage,
    },
  };
}
```

```ts
import { Request, Response } from "express";
import { adaptRequest, HttpRequest, HttpResponse } from "./http";

export function makeExpressCallback(
  controller: (req: HttpRequest) => Promise<HttpResponse> | HttpResponse
) {
  return async (req: Request, res: Response) => {
    try {
      const httpRequest = adaptRequest(req);

      const httpResponse = await controller(httpRequest);
      if (httpResponse.headers) {
        res.set(httpResponse.headers);
      }
      if (httpResponse.cookies) {
        httpResponse.cookies.forEach((cookie) =>
          res.cookie(cookie.name, cookie.value, cookie.options)
        );
      }

      if (httpResponse.statusCode === 302) {
        if (!httpResponse.redirectTo) {
          //developer error here, need to figure out a type for this case
          return res.status(500).send({ error: "An unknown error occurred." });
        }
        return res.redirect(httpResponse.redirectTo);
      }
      res.type("json");
      return res.status(httpResponse.statusCode).send(httpResponse.body);
    } catch (error) {
      return res.status(500).send({ error: "An unknown error occurred." });
    }
  };
}
```

If you are new to this whole Clean concept this might seem strange that we are creating our own interface for http modules (express already has them defined anyways right???). Well the reason we do this is because it allows us to design our codebase around our rules. If we use the express interfaces for all of our controllers then if we ever decide to migrate from express we will inevitably have to change ALL of our controllers (oof).
With our defined shape of request/response, we then create this expressCallback function. This will take one of our controllers as a callback. You'll notice it follows these steps:

- Take incoming express request and pass it to our adapter.
- Pass adapted request to our controller, which in turn returns a `HttpResponse`.
- Set the headers
- Set the cookies
- If a redirect is given, then return a `res.redirect()`, otherwise we just send back the status and data given to us by the controller.

This has two benefits:

1. We have an error handler that catches any errors we miss and returns a generic error.
2. We have completely cut express out of our application/business logic!

We are now ready to start building the app!

## A Quick Detour

Feel free to skip this part, however, if you are interested in why we are going to be building so many files and folders read on!

Part of building an effective service is laying out your project into individually testable modules. Normally, when you see examples of express API's you see a simple endpoint like this:

```ts
import {router} from "express";
import myModel from "./myModel"; //might be a mongoose model or similar ORM

router.get("/example", async(req,res) => {
    try {
        // do some things
        const things = await myModel.findAll();
        // do some more things
        // handle all edge cases etc.
        // logger call here
        // potentially many other libraries and packages doing things we need them to do in order to complete a task... you get the idea.
        res.send(things);
    } catch (error) {
        res.sendStatus(500);
    }
}
```

This is fine for an example but makes testing incredibly difficult. Let's say you want to test just the router for the response types (ensuring you are testing what is called "Application Logic"). Now you either have to mock the `myModel` import and deal with all of the overhead you're about to encounter with mocking libraries and Typescript. Or you need to create a test database. Now, you'll notice you just added a whole bunch of work to your plate and none of it relates to you testing a 200 response or a 500 response, etc.

Okay, so we know what is wrong with this code but what is the answer? The answer lies with something called "dependency injection".

Dependency injection is the idea that instead of using our imports directly (as you can see above with `myModel`), we instead inject them (via passing them as arguments). We will get into the implementation of dependency injection and what this looks like soon.

## Building From The Inside Out

Since we are implementing what is called Clean architecture we want to build our app from the 'inside out' meaning we start with our Model. If you are curious about what this looks like see the following image:



*Source: [Medium](https://miro.medium.com/v2/resize:fit:772/1*B7LkQDyDqLN3rRSrNYkETA.jpeg)\*

_[I have attached a gist to a writeup explaining Clean Code further it](https://gist.github.com/wojteklu/73c6914cc446146b8b533c0988cf8d29)_

As you can see, everything is based on **entities**. So let's make ours.

## Making the User Model

First, create a `models` directory inside of `./src`. Then, create a directory called `users` with 2 files: `index.ts` and `user.ts` inside of `./src/models`. This might seem excessive but you'll see in a minute why we do this.

Now we add our **business logic** to our `./src/models/users/user.ts` file. Below is some arbitrary logic.

```typescript

export interface User {
  id: string;
  email: string;
  version: number; // we will cover this later
}

// Factory method that returns a userFactory
// As you can see, we are Dependency injecting the Id, and isEmail method instead of importing them directly into our code

// This is a factory that returns a function that can be called to create new users
export function buildMakeUser({
  Id,
  isEmail,
}: {
  Id: { makeId: () => string; isValidId: (id: string) => boolean };
  isEmail: (val: string) => boolean;
}) {
  // The returned factory
  return async function makeUser({
    id = Id.makeId(),
    email,
    version,
  }: {
    id?: string;
    email: string;
    version: number;
  }): Promise<User> {
    if (!Id.isValidId(id)) {
      throw new Error("User must have a valid id.");
    }

    if (!isEmail(email)) {
      throw new Error("Email is invalid.");
    }
    return Object.freeze({
      id,
      email,
      version,
    });
  };
}
```

This code might look confusing at first, if you aren't familiar then let's take it one step at a time. First, we create a function called `buildMakeUser()` the reason we call it buildMake is because it is a factory that returns factories (thus the build, make). If you are curious about what a factory method is, [see this link](https://refactoring.guru/design-patterns/factory-method).

Now, we pass in our libraries/packages as arguments to our factory instead of just using them directly in our code. Why do we do this? We do this so that if we ever decide to change a package we only need to change the injection. This leads to fewer bugs and modules that are simpler to test.

You'll also notice that we are using an Id object to validate id's in our user. Let's quickly make that. In `./src/utils/id` paste the following:

```ts
import cuid from "cuid";

const Id = Object.freeze({
  makeId: cuid,
  isValidId: cuid.isCuid,
});

export default Id;
```

Now we have a User model and Id generating utility. Let's inject our dependencies. In `./src/models/users/index.ts` paste the following code:

```ts
import { buildMakeUser } from "./user";
import Id from "../../utils/Id";
import cuid from "cuid";

// Arbitrary validation method (could be a validator from lib or other)
const isEmail = (email: string) => {
  return true;
};

//export the factory for creating users initialized with the required dependencies
export default buildMakeUser({ Id, isEmail });
export * from "./user";
```

Another added bonus of using dependency injection is that since we have defined our interfaces for what things like `isEmail` should be (a method that takes a string and returns a boolean) we can actually change the library at any point down the line and as long as it adheres to our interface the business logic never changes! This is incredibly powerful for projects that carry on over years. Finally, we have created our factory that returns users and are ready to move on to the next layer... Use cases!

## Creating the "Generate Magic Link" Use Case

P.S. For brevity, we will not be creating a **Create User** use case but feel free to do so if you'd like. You should have all the tools for this refactor by the end of this post.

Okay, we have a user entity, now we want to actually create them. To do this we will create a `./src/usecases` directory and inside create a `./src/usecases/auth` directory. Inside this `./src/usecases/auth` directory, create a `generateMagicLink` directory and 2 files: `index.ts` and `generateMagicLink.ts`. Again, we do this to help organize our project but also to allow for a nice convention for dependency injection.

Now we are going to write the use case for generating a magic link. If you have any experience working in a software development environment then you'll understand that by seperating our use cases like this we make maintaining them SUPER easy. If a client wants to make changes to how generating a magic link works we need only edit this particular use case and the rest is done (no more changing 500 lines of code for a small tweak!).

```ts
import { User, makeUser } from "../../models/users";
export interface GenerateMagicLink {
  email: string;
}

export interface BuildMakeGenerateMagicLink {
  findByEmail: ({ email }: { email: string }) => Promise<User | null>;
  createUser: ({ email }: { email: string }) => Promise<User>;
  signMagicLinkToken: (payload: { email: string }) => string;
  sendMagicLinkSignUpMail: ({
    to,
    verificationToken,
  }: MagicLinkMailer) => Mailer;
  sendMagicLinkLoginMail: ({
    to,
    verificationToken,
  }: MagicLinkMailer) => Mailer;
}

export function buildMakeGenerateMagicLink({
  signMagicLinkToken,
  sendMagicLinkLoginMail,
  sendMagicLinkSignUpMail,
  findByEmail,
  createUser,
}: BuildMakeLoginEmailUser) {
  return async function makeGenerateMagicLink(data: GenerateMagicLink) {
    //find user
    let user = await findByEmail({
      email: data.email.toLowerCase(),
    });

    const verificationToken = signMagicLinkToken({ email: data.email });

    //if no user we send the signup
    if (!user) {
      const newUser = makeUser(data);
      user = await createUser(newUser);

      //Generate signup email
      await sendMagicLinkSignUpMail({
        to: data.email,
        verificationToken,
      }).send();
      return;
    }
    //otherwise we send the login template
    sendMagicLinkLoginMail({ to: data.email, verificationToken }).send();
    return;
  };
}
```

Okay so again, we have a factory that returns a factory. In this case we have a factory that builds a factory that returns a generateMagicLink use case. Here is where we are starting to see a more involved example of dependency injection. The rest is simple, just put the logic that would normally be put in your express endpoint in the use case. But remember, application logic doesn't belong here. Business logic goes here such as how we create users, what emails we send when etc. (All of the logic that DOESN'T involve sending HTTP responses or formatting headers etc.).

We start by injecting a database method (that hasn't been written yet) `findByEmail()`, as well as 2 mailer methods.

As a side note, you should always validate inputs, for this post I will not be doing so but make sure that the data object coming is has been validated either by your controller or here through assertions and handle accordingly.

Next lets create this dataAccess directory, then we will make the mailer.

So again, by this point we are used to it, create a `./src/dataAccess` directory, `./src/dataAccess/users` directory and `index.ts` `user.ts` files.

Here in our data access we want to put... well data access. Methods that we will use to access our data (things in the database). Let's write that now.

Inside of `./src/dataAccess/users/user.ts` paste the following code:

```ts
import { Db } from "mongodb";
import Id from "../utils/Id";

export interface UserDocument {
  _id: string;
  email: string;
  version: number;
}

export interface InsertUserDocument {
  id?: string;
  email: string;
  version?: number;
}

export default function makeUsersDb({ makeDb }: { makeDb: () => Promise<Db> }) {
  return Object.freeze({
    insert,
    findByEmail,
    findUserById,
    update,
  });

  async function insert({
    id: _id = Id.makeId(),
    email,
    version = 0,
  }: InsertUserDocument) {
    const db = await makeDb();
    const result = await db.collection<UserDocument>("users").insertOne({
      _id,
      email,
      version,
    });
    return { id: result.insertedId, email, version };
  }

  async function findByEmail({ email }: { email: string }) {
    const db = await makeDb();
    const result = db.collection<UserDocument>("users").find({ email });
    const found = await result.toArray();
    if (found.length === 0) {
      return null;
    }
    const { _id: id, ...info } = found[0];
    return { id, ...info };
  }
```

Here, we have implemented two methods `findByEmail()` and `insert()`. Both of these will be used in our generateMagicLink use case. Again, we need to initialize this object by dependency injecting the `makeDb()` method. Let's do that now.

In the `./src/dataAccess/users/index.ts` file paste the following:

```ts
import { Db, MongoClient } from "mongodb";
import makeUsersDb from "./usersDb";

let db: Db;
export const client = new MongoClient(url, {});

export async function makeDb() {
  if (!db) {
    await client.connect();
    db = client.db(dbName);
  }
  return db;
}

const usersDb = makeUsersDb({ makeDb });
export { usersDb };
```

Here we call our UsersDb Factory and inject our database in via makeDb (Alternatively, you could place the makeDb code elsewhere and export it).

We are now ready to inject the userDb functions into our use case. In `./src/usecases/auth/index.ts`

```ts
import { usersDb } from "../../dataAccess";
import { magicLinkMailer } from "../../mailers/loginUserMailer";
import {
  makeTokens,
  signMagicLinkToken,
  verifyMagicLinkToken,
} from "../../utils/tokenUtils";
import { buildMakeGenerateMagicLink } from "./generateMagicLink";
import { buildMakeVerifyMagicLink } from "./verifyMagicLink";

const generateMagicLink = buildMakeGenerateMagicLink({
  createUser: usersDb.insert,
  findByEmail: usersDb.findByEmail,
  sendMagicLinkLoginMail: magicLinkMailer,
  sendMagicLinkSignUpMail: magicLinkMailer,
  signMagicLinkToken: signMagicLinkToken,
});

export { generateMagicLink };
```

Now all we have left before moving on to the controller is to create those mailers.

## Creating a resuable mailer

Create a directory inside `./src` called `./src/mailers`

```ts index.ts
// Generic Mailer send call
export interface Mailer {
  send: () => Promise<void>;
}
```

Then create `./src/mailers/signupUserMailer.ts`

```ts signupUserMailer.ts
import { sendGridMailer } from "../integrations/sendgrid";

export interface SignupMagicLinkMailer {
  to: string;
  verificationToken: string;
}

export function signupMagicLinkMailer({
  to,
  verificationToken,
}: SignupMagicLinkMailer) {
  const origin = process.env.MAGIC_REDIRECT_URI;

  const inviteUrl = `${origin}?token=${verificationToken}`;

  const msg = {
    from: process.env.SENDGRID_FROM_EMAIL!,
    to,
    subject: "Signup link",
    html: `
      <h1>Below is your one time link.</h1>
      <h3>This link will expire in 15minutes.</h3>
      <a href="${inviteUrl}">
        Click here to signup.
      </a>
    `,
  };

  return {
    async send() {
      if (process.env.NODE_ENV === "production") {
        throw new Error(
          "No production email implementation in mailers/magicLinkMailer"
        );
      } else {
        await sendGridMailer.send(msg);
      }
    },
  };
}
```

This signup mailer will send out an email using the generated verification token. The token will be set as a query parameter which will be parsed by our verify method later.
To use this mailer we just take the returned object and call `.send()`

Finally create `./src/integrations/sendgrid.ts` with the following to initialize sendgrid for our application.

```ts
import mailer from "@sendgrid/mail";
mailer.setApiKey(process.env.SENDGRID_API_KEY);
export const sendGridMailer = mailer;
```

## Creating the Magiclink token

Now we need to actually make that verification token that will be used by our signup mailer.

```ts tokenUtils.ts
import { CookieOptions } from "express";
import jwt from "jsonwebtoken";

export interface Cookie {
  name: string;
  value: string;
  options: CookieOptions;
}

export interface MagicLinkTokenPayload {
  email: string;
}

export interface MagicLinkToken extends MagicLinkTokenPayload {
  exp: number;
}

export enum TokenExpiration {
  Magic = 15 * 60, //15 minutes
}

export function signMagicLinkToken(payload: MagicLinkTokenPayload) {
  return jwt.sign(payload, process.env.MAGIC_LINK_TOKEN_SECRET!, {
    expiresIn: TokenExpiration.Magic,
  });
}
```

Let's break this down.

1. Define an interface for our MagicLinkTokenPayload. This will be the data that is inserted into the JWT.
2. Create an interface for the entire MagicLinkToken (exp: short for expiration, and the email).
3. Set a constant value for the duration this token will be valid for (in this case, 15 minutes).
4. Create a signMagicLinkToken method. This method takes the payload data (email) and signs a token with the proper expiration. If you are interested in how `jwt.sign()` works check out [this link](https://www.npmjs.com/package/jsonwebtoken) for a more in-depth description.

## Creating the Controller

Okay, we have the use case and utility methods created. We have created an entity that conforms to our business logic. Now we need a place to put our application logic.
Application logic is the logic that bridges the gap between our frontend consumer and our backend usecases. Using our code as an example, business logic is any logic that would be given to us as a requirement (such as how long tokens are valid, what should happen if a user email exists, etc.). Basically, any logic that defines the rules of our app. Application logic on the otherhand is how we take that information and send it around, in our case the HTTP responses, status codes, etc.

```ts controllers/auth/magic.ts
import { HttpRequest, HttpResponse } from "../../../utils/http";
import makeHttpError from "../../../utils/http/makeError";

export interface GenerateMagicLink {
  email: string;
}

export interface MakePostMagicLink {
  generateMagicLink: (data: GenerateMagicLink) => Promise<void>;
}

export function makePostMagicLink({ generateMagicLink }: MakePostMagicLink) {
  return async function postMagicLink(req: HttpRequest): Promise<HttpResponse> {
    const headers = {
      "Content-Type": "application/json",
    };
    try {
      await generateMagicLink(req.body);

      return {
        headers,
        statusCode: 201,
      };
    } catch (error) {
      return makeHttpError({ statusCode: 400, errorMessage: error.message });
    }
  };
}
```

In this code example, you can see that we are setting headers, calling our usecase and if all goes well, we return the headers and a statuscode. As you can see, our controllers are very single purpose here, only solving the problem of returning responses to our client.

## Link up to the router

```ts
import { Router } from "express";
import authController from "../../controllers/auth";
import { authMiddleware } from "../../middlewares/authentication";
import { makeExpressCallback } from "../../utils/express-callback";
import { clearTokens } from "../../utils/tokenUtils";

const router = Router();

router.post("/magic", makeExpressCallback(authController.postMagic));

export default router;
```

Okay, here we are, finally hooking it all up to an endpoint. In the above code you can see that we are back in express land and are using our expressCallback to take our controllers postmagiclink method.
Now we have our first endpoint created! We can now successfully take input from a client, generate a one time link and email the given account an signup/login email.

## Doing it all again

Now that you have an understanding of the process, I am only going to be explaining the why of the code moving forward. We now have to create the verification endpoint.

## Verifying the Magiclink

So clients get an email with a link, they click it, then what? Right now, nothing, so let's change that.

We are going to create a usecase that handles this let's call it `./src/usecases/auth/verifyMagicLink`.

As always, we create the usecase then inject the dependencies.

```ts
import { User } from "../../dataAccess/usersDb";

export interface VerifyMagicLink {
  token: string;
}

export interface BuildMakeVerifyMagicLink {
  findByEmail: ({ email }: { email: string }) => Promise<User | null>;
  verifyMagicLinkToken: (token: string) => { email: string };
  makeTokens: (user: User) => { accessToken: string; refreshToken: string };
}

export function buildMakeVerifyMagicLink({
  findByEmail,
  verifyMagicLinkToken,
  makeTokens,
}: BuildMakeVerifyMagicLink) {
  return async function makeGenerateMagicLink(data: VerifyMagicLink) {
    try {
      const { email } = verifyMagicLinkToken(data.token);
      const user = await findByEmail({ email });
      if (!user) {
        throw new Error("No user");
      }

      const { refreshToken, accessToken } = makeTokens(user);
      return {
        user,
        accessToken,
        refreshToken,
      };
    } catch {
      throw new Error("Big oof");
    }
  };
}
```

As you can see, I have thrown generic errors here as I'm unoriginal but feel free to handle these as you would like (remember to inject the logger as a depdendency). To break this above code down we start by verifying the token (not written yet) to ensure that it has not been tampered with or changed or expired. Then we lookup the email that was inside the payload. Remember, we signed a token with the email being the only item in the payload, when we decode this token we also can get access to that email.
We then lookup the user via email. If those two things go as planned then we can generate what is called an 'access token' and a 'refresh token'. This is where we get into the interesting bits so read on.

_Note that we never took a password for creating an account. The way that authentication works is with a public/private keypair. The public key would normally be an email/username but the private key is normally a password that only you know.
Well we can entirely avoid requiring a password by simply sending an email that is shortlived to the user. By virtue of the user clicking our link they prove ownership of the email, thus the email link being clicked is the private key in this instance._

## Access Token / Refresh Token Flow

So what are access tokens and refresh tokens?

Well, remember, since we aren't using sessions we cannot persist state in a database, instead we chose to go with JWT's.
With JWT's we can prevent needing to lookup user's in the database everytime they make a request. JWT's are tamperproof meaning that if it is modified then we will know when we go to decode it. However, after a few years of development I have seen instances of JWT's being used improperly.

It is important to set an expiration time for the token, this will prevent a malicious user from getting that token and being able to impersonate their victim forever. In our scheme we will be issuing 2 tokens: an access token and a refresh token, first the access token.

The access token will be a short-lived token (5 minutes) that will be used exactly as the name suggests, to access things.
Now I know what you're thinking _'If they can only access things for 5 minutes then what happens when it expires?'_, which is a valid question, this is where our refresh token comes in.
Our refresh token will be much longer lived (in our case 7 days).

The refresh token will be sent when the access token expires to get a new access token. In our code, we will have an endpoint for obtaining a new access token, whereas when a new refresh token is needed the user will need to login again.
Below is the token logic which is located in `./src/utils/tokenUtils.ts` (expanded on from our earlier token code).

```ts
import { CookieOptions, Response } from "express";

import jwt from "jsonwebtoken";
import { User } from "../models/user";

export interface MagicLinkTokenPayload {
  email: string;
}

export interface MagicLinkToken extends MagicLinkTokenPayload {
  exp: number;
}

export interface AccessTokenPayload {
  userId: string;
  email: string;
}

export interface AccessToken extends AccessTokenPayload {
  exp: number;
}

export interface RefreshTokenPayload {
  userId: string;
  version: number;
  email: string;
}

export interface RefreshToken extends RefreshTokenPayload {
  exp: number;
}

export enum TokenExpiration {
  Access = 5 * 60, // 5 minutes
  Refresh = 7 * 24 * 60 * 60, // 7 days
  Magic = 15 * 60, //15 minutes
  RefreshIfLessThan = 4 * 24 * 60 * 60, // 4 days
}

export enum Cookies {
  AccessToken = "access",
  RefreshToken = "refresh",
}

export interface Cookie {
  name: string;
  value: string;
  options: CookieOptions;
}

export interface MakeTokenParams {
  tokenType: Cookies.AccessToken | Cookies.RefreshToken;
  payload: string;
}

const isProduction = process.env.NODE_ENV === "production";

export const defaultCookieOptions: CookieOptions = {
  httpOnly: true,
  secure: isProduction,
  sameSite: isProduction ? "strict" : "lax",
  domain: process.env.BASE_DOMAIN,
  path: "/",
};

export const refreshTokenCookieOptions: CookieOptions = {
  ...defaultCookieOptions,
  maxAge: TokenExpiration.Refresh * 1000,
};

export const accessTokenCookieOptions: CookieOptions = {
  ...defaultCookieOptions,
  maxAge: TokenExpiration.Access * 1000,
};

export function signAccessToken(payload: AccessTokenPayload) {
  return jwt.sign(payload, process.env.ACCESS_TOKEN_SECRET!, {
    expiresIn: TokenExpiration.Access,
  });
}

export function signRefreshToken(payload: AccessTokenPayload) {
  return jwt.sign(payload, process.env.REFRESH_TOKEN_SECRET!, {
    expiresIn: TokenExpiration.Refresh,
  });
}

export function signMagicLinkToken(payload: MagicLinkTokenPayload) {
  return jwt.sign(payload, process.env.MAGIC_LINK_TOKEN_SECRET!, {
    expiresIn: TokenExpiration.Magic,
  });
}

export const makeTokens = (user: User) => {
  // generate the payloads
  const accessPayload: AccessTokenPayload = {
    userId: user.id,
    email: user.email,
  };
  const refreshPayload: RefreshTokenPayload = {
    userId: user.id,
    email: user.email,
    version: user.version,
  };

  // sign tokens
  const accessToken = signAccessToken(accessPayload);
  const refreshToken = refreshPayload && signRefreshToken(refreshPayload);

  return {
    accessToken,
    refreshToken,
  };
};

export const setToken = ({ tokenType, payload }: MakeTokenParams): Cookie => {
  if (tokenType === "access") {
    return {
      name: Cookies.AccessToken,
      value: payload,
      options: accessTokenCookieOptions,
    };
  }
  return {
    name: Cookies.RefreshToken,
    value: payload,
    options: refreshTokenCookieOptions,
  };
};

export const verifyRefreshToken = (token: string) => {
  return jwt.verify(token, process.env.REFRESH_TOKEN_SECRET!) as RefreshToken;
};

export const verifyAccessToken = (token: string) => {
  return jwt.verify(token, process.env.ACCESS_TOKEN_SECRET!) as AccessToken;
};

export const verifyMagicLinkToken = (token: string) => {
  return jwt.verify(
    token,
    process.env.MAGIC_LINK_TOKEN_SECRET!
  ) as MagicLinkToken;
};

export function refreshTokens(current: RefreshToken, tokenVersion: number) {
  if (tokenVersion !== current.version) {
    throw "Token Revoked";
  }

  const accessPayload: AccessTokenPayload = {
    userId: current.userId,
    email: current.email,
  };
  const accessToken = signAccessToken(accessPayload);

  let refreshPayload: RefreshTokenPayload | undefined;

  const expiration = new Date(current.exp * 1000);
  const now = new Date();
  const secondsUntilExpiration = (expiration.getTime() - now.getTime()) / 1000;

  if (secondsUntilExpiration < TokenExpiration.RefreshIfLessThan) {
    refreshPayload = {
      userId: current.userId,
      email: current.email,
      version: tokenVersion,
    };
  }
  const refreshToken = refreshPayload && signRefreshToken(refreshPayload);

  return { accessToken, refreshToken };
}

export function clearTokens(res: Response) {
  // return cookie.serialize(Cookies.AccessToken, "", { ...defaultCookieOptions });

  res.cookie(Cookies.AccessToken, "", { ...defaultCookieOptions, maxAge: 0 });
  res.cookie(Cookies.RefreshToken, "", { ...defaultCookieOptions, maxAge: 0 });
}

export const clearToken = (tokenType: Cookies): Cookie => {
  return tokenType === Cookies.AccessToken
    ? {
        name: Cookies.AccessToken,
        value: "",
        options: { ...defaultCookieOptions, maxAge: 0 },
      }
    : {
        name: Cookies.RefreshToken,
        value: "",
        options: { ...defaultCookieOptions, maxAge: 0 },
      };
};
```

I know that there is a lot but we will go through it thoroughly.

Firstly, the interfaces.

Our `MagicLinkTokenPayload` has been covered earlier but outlines what fields will be in the JWT for the magiclink token. This is the token/payload that is sent when requesting a magiclink to login with.

`AccessTokenPayload` contains the users unique identifier as well as email, you can put whatever you'd like in your JWT's but for 99% of my uses I will only need the users id, email, or maybe additional information such as a role. Remember since they are signed/tamper-proof we can send these fields to our frontend (React, etc.) and they will be able to read the values here.

`RefreshTokenPayload` contains the user id, email, and this version field.
The version field is a unique/random value we will assign to the refresh token to ensure that destructive actions are applied to all loggedin sessions.
For example, when a user logs in to the application on their phone as well as their desktop, and they change the password, we will update the version.
This allows us to perform actions that are normally very difficult (if not impossible) with a simple JWT implementation. When performing a function such as logging out everywhere, updating passwords, etc.
we can simply modify the version value and now all related sessions will be logged out after their access tokens expire.

We then have our `exp` or expiration that is just a number which represents a point in time.

After our interfaces we have our cookie options, we will be sending these JWT's as cookie headers to the clients. By sending them as [httponly cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie#httponly) we prevent the issue of XSS, and by setting the sameSite attribute as 'strict' (in production) we prevent another common security concern of [CSRF](https://developer.mozilla.org/en-US/docs/Web/Security/Types_of_attacks#cross-site_request_forgery_csrf).
We then set our cookie options and maxAges, there is no guarantee that the client will resepct these expirations but we set the as a best practice on our end.

_It is important to note that since we have made the cookie httponly, the frontend consumer will not be able to access the values in the cookie. Instead, it will need to request the data for the user (for things such as avatar, role, etc. via an endpoint). A workaround to this would be to allow the `AccessToken` to be sent and stored in local storage (or another mechanism accessible via JavaScript). This would have security risks, however, since the token is only shortlived, it may be a viable option in your usecase._

After that we have our functions that let us perform the signing/verification.

`signAccessToken`/`signRefreshToken`/`signMagicLinkToken` all do the same thing with the except of setting the `expiresIn` property to a value based on our `TokenExpiration` enum.

Our verify methods will simply verify the tokens with our secret and ensure no tampering has happened.

Finally, the `refreshTokens()` method. This method will taken the current refresh token and first check to see if the versions match up, remember from earlier that if they don't then we revoke this token from the user. Otherwise, we will then create the new access token, check to see if the refresh token is within a certain threshold for expiration and, if it is, send a new refresh token with a new 7 day expiration. This will allow the user to continue to remain logged in as long as they make a request within 7 days giving a very nice boost to UX.

I know that there was a lot here but most of this was taken from a phenominal video by flolu that [I have linked here.](https://youtu.be/xMsJPnjiRAc?si=lIUb7OuTgbiJabJ8) please check it out.

## Wrap up

To summarize, we have covered designing applications using the Clean design principle, learned the importance of DI and how it helps immensely in testing your application, the logic for passwordless authentication, as well as JWT's and how we can utilize them to give huge UX benefits without comprimising security.

The following code covers the controller, usecase, and linking to the router.

First, the magiclink verification controller/usecase
`./src/controllers/auth/magicLink.ts`

```ts
import { User } from "../../../models/user";
import { HttpRequest, HttpResponse } from "../../../utils/http";
import makeHttpError from "../../../utils/http/makeError";
import { Cookie, Cookies, MakeTokenParams } from "../../../utils/tokenUtils";

export interface VerifyMagicLink {
  token: string;
}

export interface MakeGetMagicLink {
  verifyMagicLink: (
    data: VerifyMagicLink
  ) => Promise<{ user: User; accessToken: string; refreshToken: string }>;
  setToken: ({ payload, tokenType }: MakeTokenParams) => Cookie;
}
export function makeGetMagicLink({
  verifyMagicLink,
  setToken,
}: MakeGetMagicLink) {
  return async function getMagicLink(req: HttpRequest): Promise<HttpResponse> {
    const headers = {
      "Content-Type": "application/json",
    };
    try {
      const { token } = req.queryParams;
      if (!token) {
        return makeHttpError({ statusCode: 400 });
      }

      const { accessToken, refreshToken } = await verifyMagicLink({
        token,
      });

      // We have confirmed the magiclink, generated an access and refresh token
      // now we set the tokens as headers and return to our expressAdapter to set as 'Set-Cookie' headers
      const access = setToken({
        payload: accessToken,
        tokenType: Cookies.AccessToken,
      });
      const refresh = setToken({
        payload: refreshToken,
        tokenType: Cookies.RefreshToken,
      });
      const tokens = [access, refresh];

      return {
        headers,
        cookies: tokens,
        statusCode: 302,
        redirectTo: process.env.CLIENT_URL,
      };
    } catch (e) {
      return makeHttpError({ statusCode: 400 });
    }
  };
}
```

Now, the refresh token controller/usecase.

```ts
import { User } from "../../models/user";
import { RefreshToken } from "../../utils/tokenUtils";

export interface MakeRefreshTokens {
  token?: string;
}

export interface BuildMakeRefreshTokens {
  verifyRefreshToken: (token: string) => RefreshToken;
  findUserById: ({ id }: { id: string }) => Promise<User | null>;
  refreshTokens: (
    current: RefreshToken,
    version: number
  ) => { refreshToken?: string; accessToken: string };
}
export function BuildMakeRefreshTokens({
  verifyRefreshToken,
  findUserById,
  refreshTokens,
}: BuildMakeRefreshTokens) {
  return async function makeRefreshTokens(data: MakeRefreshTokens) {
    // Check for existence
    if (!data.token) {
      throw new Error("No authentication token.");
    }
    // Ensure it is a valid token (it has the correct version #)
    const current = verifyRefreshToken(data.token);
    // Find the decoded user from token
    const user = await findUserById({ id: current.userId });

    if (!user) {
      throw new Error("User not found");
    }
    // Everything checks out, update the tokens
    const { accessToken, refreshToken } = refreshTokens(current, user.version);
    return {
      accessToken,
      refreshToken,
    };
  };
}
```

Again, we just need to implement the logic that handles access/refresh tokens. This usecase will take the incoming tokens, and run our earlier defined `refreshTokens()` method.

Linking it up to our controller

```ts
import { HttpRequest, HttpResponse } from "../../../utils/http";
import makeHttpError from "../../../utils/http/makeError";
import { Cookie, Cookies, MakeTokenParams } from "../../../utils/tokenUtils";

export interface MakePostRefresh {
  refreshTokens: (data: {
    token: string;
  }) => Promise<{ accessToken: string; refreshToken?: string }>;
  setToken: ({ payload, tokenType }: MakeTokenParams) => Cookie;
  clearToken: (tokenType: Cookies) => Cookie;
}

export function makePostRefresh({
  refreshTokens,
  setToken,
  clearToken,
}: MakePostRefresh) {
  return async function postRefresh(req: HttpRequest): Promise<HttpResponse> {
    const headers = {
      "Content-Type": "application/json",
    };
    try {
      //parse out the token from cookie header
      const token = req.cookies[Cookies.RefreshToken];

      // run refresh usecase
      const { accessToken, refreshToken } = await refreshTokens({
        token: token,
      });

      const tokens: Cookie[] = [];

      const access = setToken({
        payload: accessToken,
        tokenType: Cookies.AccessToken,
      });
      tokens.push(access);

      let refresh;
      // if we are issuing a new refresh token (as per UC)
      if (refreshToken) {
        refresh = setToken({
          payload: refreshToken,
          tokenType: Cookies.RefreshToken,
        });
        tokens.push(refresh);
      }

      return {
        headers,
        cookies: tokens,
        statusCode: 200,
      };
    } catch (error) {
      clearToken(Cookies.AccessToken);
      clearToken(Cookies.RefreshToken);
      return makeHttpError({ statusCode: 400, errorMessage: error.message });
    }
  };
}
```

And finally, linking these new endpoints up to our express router. The /logout endpoint was simple enough that a usecase would be unnecessary in my opinion.

```ts
import { Router } from "express";
import authController from "../../controllers/auth";
import { authMiddleware } from "../../middlewares/authentication";
import { makeExpressCallback } from "../../utils/express-callback";
import { clearTokens } from "../../utils/tokenUtils";

const router = Router();

router.post("/magic", makeExpressCallback(authController.postMagic));

router.get("/magic", makeExpressCallback(authController.getMagic));

router.post("/refresh", makeExpressCallback(authController.postRefresh));

//locally logout (not worth breaking into callback)
router.post("/logout", authMiddleware, (_req, res) => {
  clearTokens(res);
  res.send({ message: "Logged out." });
});

export default router;
```

As a final fun task, try and setup a /logout all endpoint. The usecase would just need to modify the version property on the user document and therefore logout all instances on other devices.

## Extra Frontend Axios implementation

If you are wondering about a starting point for using this new api on your frontend, consider the following code.

```ts
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from "axios";

export const getError = (error: any) => {
  if (error.isAxiosError && error.response) {
    return error.response.data.error.message;
  }
  return "Unexpected error";
};

export const makeAxiosApi = (baseUrl: string) => {
  const api = axiosAdapter(baseUrl);

  return {
    get: api.get,
    post: api.post,
    patch: api.patch,
    errorHandler: api.errorHandler,
    deleteReq: api.deleteReq,
  };
};

const axiosAdapter = (baseUrl: string) => {
  const api: AxiosInstance = axios.create({
    baseURL: baseUrl,
    timeout: 30000,
    withCredentials: true,
  });

  async function get(
    url: string,
    config?: AxiosRequestConfig
  ): Promise<AxiosResponse> {
    return await api.get(url, config);
  }

  async function post(
    url: string,
    body?: unknown,
    config?: AxiosRequestConfig
  ): Promise<AxiosResponse> {
    return await api.post(url, body, config);
  }

  async function patch(
    url: string,
    body?: unknown,
    config?: AxiosRequestConfig
  ): Promise<AxiosResponse> {
    return await api.patch(url, body, config);
  }
  async function deleteReq(
    url: string,
    config?: AxiosRequestConfig
  ): Promise<AxiosResponse> {
    return await api.delete(url, config);
  }

  return {
    get,
    post,
    patch,
    deleteReq,
  };
};
```

The above code will create an axios instance for you that will simplify your code by providing a single instance to work with.

Now we want to handle the case of access tokens expiring. This can be achieved with the following:

```ts
import { AxiosRequestConfig, AxiosResponse } from "axios";

import { Http, QueryResponse } from "./interfaces";

export type QueryResponse<T> = T;

export interface Http {
  get: <T>(
    url: string,
    config?: AxiosRequestConfig,
  ) => Promise<QueryResponse<T>>;
  post: <T>(
    url: string,
    body?: any,
    config?: AxiosRequestConfig,
  ) => Promise<QueryResponse<T>>;
  patch: <T>(
    url: string,
    body?: any,
    config?: AxiosRequestConfig,
  ) => Promise<QueryResponse<T>>;
  deleteReq: <T>(
    url: string,
    config?: AxiosRequestConfig,
  ) => Promise<QueryResponse<T>>;
}

export interface HttpResponse {
  data?: any;
  status: number;
}

export interface HttpResponseError {
  error: {
    message?: string;
  };
  success: boolean;
}

export HttpResponse;


export type HttpErrorHandler = (error: unknown) => void;

export const makeHttp = (
  httpLib: any,
  errorHandler: HttpErrorHandler,
): Http => {
  return {
    get,
    post,
    patch,
    deleteReq,
  };

  async function refreshTokens() {
    await httpLib.post("/auth/refresh");
  }

  // If we make a request and it returns a 401, try and refresh our tokens then try request again
  // if the request still returns a 401, we throw that error
  // if the request doesnt throw we got our data
  // if the request does throw but it isnt a 401 we throw
  async function handleRequest(
    request: () => Promise<AxiosResponse>,
  ): Promise<AxiosResponse> {
    try {
      return await request();
    } catch (error: any) {
      if (error?.response?.status === 401) {
        try {
          await refreshTokens();
          return await request();
        } catch (innerError: any) {
          throw errorHandler(innerError);
        }
      }

      throw errorHandler(error);
    }
  }

  async function get<T>(
    url: string,
    config?: AxiosRequestConfig,
  ): Promise<QueryResponse<T>> {
    const request = () => httpLib.get(url, config);
    return await (
      await handleRequest(request)
    ).data;
  }
  async function post<T>(
    url: string,
    body?: unknown,
    config?: AxiosRequestConfig,
  ): Promise<QueryResponse<T>> {
    const request = () => httpLib.post(url, body, config);
    return await (
      await handleRequest(request)
    ).data;
  }

  async function patch<T>(
    url: string,
    body?: unknown,
    config?: AxiosRequestConfig,
  ): Promise<QueryResponse<T>> {
    const request = () => httpLib.patch(url, body, config);
    return await (
      await handleRequest(request)
    ).data;
  }

  async function deleteReq<T>(
    url: string,
    config?: AxiosRequestConfig,
  ): Promise<QueryResponse<T>> {
    const request = () => httpLib.delete(url, config);
    return await (
      await handleRequest(request)
    ).data;
  }
};
```

By using this new http lib we have done a few things: we have setup axios to create a reusable instance, we have abstracted axios out of our httplib (with exception of interfaces for brevity), we have created a interceptor that will handle the case of an expired access token.
This let's our frontend seamlessly request a new access token without interupting the applications functionality.

Beautiful! Happy coding.