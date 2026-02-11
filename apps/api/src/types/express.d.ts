declare namespace Express {
  interface Request {
    user?: {
      id: string;
      email: string;
      plan: string;
      isAdmin: boolean;
    };
  }
}
