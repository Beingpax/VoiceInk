import { render, screen, act } from '@testing-library/react';
import App from './App';
import { vi } from 'vitest';

vi.mock('./whisper');

test('renders the app', async () => {
  await act(async () => {
    render(<App />);
  });
  const heading = screen.getByText(/VoiceInk/i);
  expect(heading).toBeInTheDocument();
});
