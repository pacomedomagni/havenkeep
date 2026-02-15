declare namespace Express {
  interface Request {
    user?: {
      id: string;
      email: string;
      plan: 'free' | 'premium';
      isAdmin: boolean;
      isPartner: boolean;
      planExpiresAt?: string | null;
    };
  }
}
