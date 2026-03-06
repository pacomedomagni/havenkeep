import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import AuthForm from '@/components/auth-form';

describe('AuthForm', () => {
  it('renders title and subtitle', () => {
    render(
      <AuthForm title="Sign In" subtitle="Welcome back">
        <div>form content</div>
      </AuthForm>
    );
    expect(screen.getByText('Sign In')).toBeInTheDocument();
    expect(screen.getByText('Welcome back')).toBeInTheDocument();
  });

  it('renders children inside the card', () => {
    render(
      <AuthForm title="Sign In" subtitle="Welcome back">
        <input placeholder="Email address" />
      </AuthForm>
    );
    expect(screen.getByPlaceholderText('Email address')).toBeInTheDocument();
  });

  it('renders the footer when provided', () => {
    render(
      <AuthForm
        title="Sign In"
        subtitle="Welcome back"
        footer={<span>Don&apos;t have an account? Sign up</span>}
      >
        <div>form content</div>
      </AuthForm>
    );
    expect(screen.getByText(/Don't have an account\? Sign up/i)).toBeInTheDocument();
  });

  it('does not render footer section when footer prop is not provided', () => {
    render(
      <AuthForm title="Create Account" subtitle="Fill in your details">
        <div>form content</div>
      </AuthForm>
    );
    // The conditional footer wrapper is not rendered when footer prop is absent
    // We verify by checking that no element with role=contentinfo or the footer text appears
    expect(screen.queryByText(/already have an account/i)).not.toBeInTheDocument();
    // Also verify the footer container class is not present
    const footerDiv = document.querySelector('.text-center.mt-4');
    expect(footerDiv).toBeNull();
  });
});
