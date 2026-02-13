import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { AppError } from './errorHandler';
import { query } from '../db';
import { isTokenBlacklisted } from '../utils/token-blacklist';

// Re-export Request as AuthRequest for backward compatibility
export type AuthRequest = Request;

export async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction
) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError('No token provided', 401);
    }

    const token = authHeader.substring(7);

    // Check if token has been revoked
    if (await isTokenBlacklisted(token)) {
      throw new AppError('Token has been revoked', 401);
    }

    const decoded = jwt.verify(token, config.jwt.secret) as {
      userId: string;
      email: string;
    };

    // Get user from database
    const result = await query(
      `SELECT u.id, u.email, u.plan, u.is_admin,
              (EXISTS(SELECT 1 FROM partners p WHERE p.user_id = u.id AND p.is_active = TRUE)) as is_partner
       FROM users u WHERE u.id = $1`,
      [decoded.userId]
    );

    if (result.rows.length === 0) {
      throw new AppError('Invalid token', 401);
    }

    req.user = {
      id: result.rows[0].id,
      email: result.rows[0].email,
      plan: result.rows[0].plan,
      isAdmin: result.rows[0].is_admin,
      isPartner: result.rows[0].is_partner,
    };

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError('Invalid token', 401));
    } else {
      next(error);
    }
  }
}

export function requireAdmin(
  req: Request,
  res: Response,
  next: NextFunction
) {
  if (!req.user?.isAdmin) {
    throw new AppError('Admin access required', 403);
  }
  next();
}

export function requirePremium(
  req: Request,
  res: Response,
  next: NextFunction
) {
  if (req.user?.plan !== 'premium') {
    throw new AppError('Premium plan required', 403);
  }
  next();
}
