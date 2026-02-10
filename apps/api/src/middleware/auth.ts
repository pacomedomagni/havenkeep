import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { AppError } from './errorHandler';
import { query } from '../db';

export interface AuthRequest extends Request {
  user?: {
    id: string;
    email: string;
    plan: string;
    isAdmin: boolean;
  };
}

export async function authenticate(
  req: AuthRequest,
  res: Response,
  next: NextFunction
) {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError(401, 'No token provided');
    }
    
    const token = authHeader.substring(7);
    
    const decoded = jwt.verify(token, config.jwt.secret) as {
      userId: string;
      email: string;
    };
    
    // Get user from database
    const result = await query(
      `SELECT id, email, plan, is_admin FROM users WHERE id = $1`,
      [decoded.userId]
    );
    
    if (result.rows.length === 0) {
      throw new AppError(401, 'Invalid token');
    }
    
    req.user = {
      id: result.rows[0].id,
      email: result.rows[0].email,
      plan: result.rows[0].plan,
      isAdmin: result.rows[0].is_admin,
    };
    
    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new AppError(401, 'Invalid token'));
    } else {
      next(error);
    }
  }
}

export function requireAdmin(
  req: AuthRequest,
  res: Response,
  next: NextFunction
) {
  if (!req.user?.isAdmin) {
    throw new AppError(403, 'Admin access required');
  }
  next();
}

export function requirePremium(
  req: AuthRequest,
  res: Response,
  next: NextFunction
) {
  if (req.user?.plan !== 'premium') {
    throw new AppError(403, 'Premium plan required');
  }
  next();
}
