import { useState, useEffect } from 'react';
import {
  Box,
  Container,
  Typography,
  Button,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  AppBar,
  Toolbar,
  Alert,
  CircularProgress,
  FormControlLabel,
  Switch,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  IconButton,
  InputAdornment,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
} from '@mui/material';
import {
  Add as AddIcon,
  Logout as LogoutIcon,
  Edit as EditIcon,
  Warning as WarningIcon,
  Schedule as ScheduleIcon,
  Search as SearchIcon,
} from '@mui/icons-material';
import { boothsApi, Booth, OperatingHours } from '../api/client';

export default function Dashboard() {
  const [booths, setBooths] = useState<Booth[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [editingBooth, setEditingBooth] = useState<Booth | null>(null);
  const [editingHoursBooth, setEditingHoursBooth] = useState<Booth | null>(null);
  const [newBoothId, setNewBoothId] = useState('');
  const [newBoothName, setNewBoothName] = useState('');
  const [editName, setEditName] = useState('');
  const [operatingHours, setOperatingHours] = useState<OperatingHours>({
    enabled: false,
    schedule: [],
  });
  const [error, setError] = useState('');
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => {
    loadBooths();
    const interval = setInterval(loadBooths, 30000);
    return () => clearInterval(interval);
  }, []);

  const loadBooths = async () => {
    try {
      const data = await boothsApi.getAll();
      setBooths(data);
      setError('');
    } catch (error) {
      console.error('Failed to load booths:', error);
      setError('Failed to load booths');
    } finally {
      setLoading(false);
    }
  };

  const handleAddBooth = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    try {
      await boothsApi.create(newBoothId, newBoothName || undefined);
      setShowAddModal(false);
      setNewBoothId('');
      setNewBoothName('');
      loadBooths();
    } catch (error: any) {
      setError(error.response?.data?.message || 'Failed to create booth');
    }
  };

  const handleEditBooth = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingBooth) return;
    setError('');
    try {
      await boothsApi.update(editingBooth.id, editName);
      setEditingBooth(null);
      setEditName('');
      loadBooths();
    } catch (error: any) {
      setError(error.response?.data?.message || 'Failed to update booth');
    }
  };

  const handleEditOperatingHours = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingHoursBooth) return;
    setError('');
    try {
      await boothsApi.updateOperatingHours(editingHoursBooth.id, operatingHours);
      setEditingHoursBooth(null);
      setOperatingHours({ enabled: false, schedule: [] });
      loadBooths();
    } catch (error: any) {
      setError(error.response?.data?.message || 'Failed to update operating hours');
    }
  };

  const addScheduleEntry = () => {
    setOperatingHours({
      ...operatingHours,
      schedule: [
        ...operatingHours.schedule,
        { day: 0, start: '09:00', end: '17:00' },
      ],
    });
  };

  const removeScheduleEntry = (index: number) => {
    setOperatingHours({
      ...operatingHours,
      schedule: operatingHours.schedule.filter((_, i) => i !== index),
    });
  };

  const updateScheduleEntry = (
    index: number,
    field: 'day' | 'start' | 'end',
    value: string | number,
  ) => {
    const newSchedule = [...operatingHours.schedule];
    newSchedule[index] = { ...newSchedule[index], [field]: value };
    setOperatingHours({ ...operatingHours, schedule: newSchedule });
  };

  const getStatusColor = (
    status: string,
    isStale: boolean,
    isWithinHours: boolean,
  ): 'error' | 'warning' | 'success' | 'default' => {
    if (status === 'offline' && !isWithinHours) return 'default';
    if (isStale && isWithinHours) return 'error';
    if (status === 'error') return 'error';
    if (status === 'warning') return 'warning';
    if (status === 'healthy') return 'success';
    return 'default';
  };

  const getStatusLabel = (status: string, isStale: boolean, isWithinHours: boolean) => {
    if (status === 'offline' && !isWithinHours) return 'Offline (Expected)';
    if (isStale && isWithinHours) return 'Stale';
    return status.charAt(0).toUpperCase() + status.slice(1);
  };

  const handleLogout = () => {
    localStorage.removeItem('token');
    window.location.reload();
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="100vh">
        <CircularProgress />
      </Box>
    );
  }

  const filterBooths = (boothList: Booth[]) => {
    if (!searchQuery.trim()) {
      return boothList;
    }
    const query = searchQuery.toLowerCase().trim();
    return boothList.filter(
      (b) =>
        b.boothId.toLowerCase().includes(query) ||
        (b.name && b.name.toLowerCase().includes(query))
    );
  };

  const boothsWithIssues = filterBooths(
    booths.filter(
      (b) =>
        (b.isStale && b.isWithinOperatingHours) ||
        b.status === 'error' ||
        (b.status === 'warning' && b.isWithinOperatingHours)
    )
  );

  const allBoothsFiltered = filterBooths(booths);

  return (
    <Box sx={{ minHeight: '100vh', bgcolor: 'grey.50' }}>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            Photobooth Dashboard
          </Typography>
          <Button
            color="inherit"
            startIcon={<AddIcon />}
            onClick={() => setShowAddModal(true)}
            sx={{ mr: 2 }}
          >
            Add Booth
          </Button>
          <Button color="inherit" startIcon={<LogoutIcon />} onClick={handleLogout}>
            Logout
          </Button>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ py: 4 }}>
        {error && (
          <Alert severity="error" sx={{ mb: 3 }} onClose={() => setError('')}>
            {error}
          </Alert>
        )}

        <Box sx={{ mb: 3 }}>
          <TextField
            fullWidth
            placeholder="Search by booth ID or name..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon />
                </InputAdornment>
              ),
            }}
            sx={{ maxWidth: 600 }}
          />
        </Box>

        {boothsWithIssues.length > 0 && (
          <Box sx={{ mb: 4 }}>
            <Typography variant="h5" gutterBottom sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <WarningIcon color="error" />
              Booths with Issues ({boothsWithIssues.length})
            </Typography>
            <TableContainer component={Paper} sx={{ mt: 2 }}>
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell>Name</TableCell>
                    <TableCell>Booth ID</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Mode</TableCell>
                    <TableCell>Timezone</TableCell>
                    <TableCell>Last Ping</TableCell>
                    <TableCell>Operating Hours</TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {boothsWithIssues.map((booth) => (
                    <BoothRow
                      key={booth.id}
                      booth={booth}
                      getStatusColor={getStatusColor}
                      getStatusLabel={getStatusLabel}
                      onEdit={() => {
                        setEditingBooth(booth);
                        setEditName(booth.name || '');
                      }}
                      onEditHours={() => {
                        setEditingHoursBooth(booth);
                        setOperatingHours(booth.operatingHours);
                      }}
                    />
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </Box>
        )}

        <Box>
          <Typography variant="h5" gutterBottom>
            All Booths ({searchQuery ? `${allBoothsFiltered.length} of ${booths.length}` : booths.length})
          </Typography>
          {searchQuery && allBoothsFiltered.length === 0 && (
            <Alert severity="info" sx={{ mt: 2 }}>
              No booths found matching "{searchQuery}"
            </Alert>
          )}
          <TableContainer component={Paper} sx={{ mt: 2 }}>
            <Table>
              <TableHead>
                <TableRow>
                  <TableCell>Name</TableCell>
                  <TableCell>Booth ID</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Mode</TableCell>
                  <TableCell>Timezone</TableCell>
                  <TableCell>Last Ping</TableCell>
                  <TableCell>Operating Hours</TableCell>
                  <TableCell align="right">Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {allBoothsFiltered.map((booth) => (
                  <BoothRow
                    key={booth.id}
                    booth={booth}
                    getStatusColor={getStatusColor}
                    getStatusLabel={getStatusLabel}
                    onEdit={() => {
                      setEditingBooth(booth);
                      setEditName(booth.name || '');
                    }}
                    onEditHours={() => {
                      setEditingHoursBooth(booth);
                      setOperatingHours(booth.operatingHours || { enabled: false, schedule: [] });
                    }}
                  />
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Box>
      </Container>

      <Dialog open={showAddModal} onClose={() => setShowAddModal(false)} maxWidth="sm" fullWidth>
        <form onSubmit={handleAddBooth}>
          <DialogTitle>Add New Booth</DialogTitle>
          <DialogContent>
            <TextField
              autoFocus
              margin="dense"
              label="Booth ID"
              fullWidth
              required
              value={newBoothId}
              onChange={(e) => setNewBoothId(e.target.value)}
              sx={{ mb: 2 }}
            />
            <TextField
              margin="dense"
              label="Name (optional)"
              fullWidth
              value={newBoothName}
              onChange={(e) => setNewBoothName(e.target.value)}
            />
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setShowAddModal(false)}>Cancel</Button>
            <Button type="submit" variant="contained">
              Add Booth
            </Button>
          </DialogActions>
        </form>
      </Dialog>

      <Dialog
        open={!!editingBooth}
        onClose={() => setEditingBooth(null)}
        maxWidth="sm"
        fullWidth
      >
        <form onSubmit={handleEditBooth}>
          <DialogTitle>Edit Booth Name</DialogTitle>
          <DialogContent>
            <TextField
              margin="dense"
              label="Booth ID"
              fullWidth
              value={editingBooth?.boothId || ''}
              disabled
              sx={{ mb: 2 }}
            />
            <TextField
              autoFocus
              margin="dense"
              label="Name"
              fullWidth
              required
              value={editName}
              onChange={(e) => setEditName(e.target.value)}
            />
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setEditingBooth(null)}>Cancel</Button>
            <Button type="submit" variant="contained">
              Save
            </Button>
          </DialogActions>
        </form>
      </Dialog>

      <Dialog
        open={!!editingHoursBooth}
        onClose={() => setEditingHoursBooth(null)}
        maxWidth="md"
        fullWidth
      >
        <form onSubmit={handleEditOperatingHours}>
          <DialogTitle>Edit Operating Hours</DialogTitle>
          <DialogContent>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              Booth: {editingHoursBooth?.name || editingHoursBooth?.boothId}
            </Typography>
            {editingHoursBooth?.timezone && (
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                Timezone: {editingHoursBooth.timezone}
              </Typography>
            )}
            <FormControlLabel
              control={
                <Switch
                  checked={operatingHours.enabled}
                  onChange={(e) =>
                    setOperatingHours({ ...operatingHours, enabled: e.target.checked })
                  }
                />
              }
              label="Enable Operating Hours Schedule"
              sx={{ mb: 2 }}
            />
            {operatingHours.enabled && (
              <Box>
                <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
                  <Typography variant="subtitle2">Schedule</Typography>
                  <Button size="small" onClick={addScheduleEntry}>
                    Add Day
                  </Button>
                </Box>
                {operatingHours.schedule.map((entry, index) => (
                  <Box
                    key={index}
                    display="flex"
                    gap={2}
                    alignItems="center"
                    mb={2}
                    flexWrap="wrap"
                  >
                    <FormControl size="small" sx={{ minWidth: 120 }}>
                      <InputLabel>Day</InputLabel>
                      <Select
                        value={entry.day}
                        label="Day"
                        onChange={(e) =>
                          updateScheduleEntry(index, 'day', Number(e.target.value))
                        }
                      >
                        <MenuItem value={0}>Sunday</MenuItem>
                        <MenuItem value={1}>Monday</MenuItem>
                        <MenuItem value={2}>Tuesday</MenuItem>
                        <MenuItem value={3}>Wednesday</MenuItem>
                        <MenuItem value={4}>Thursday</MenuItem>
                        <MenuItem value={5}>Friday</MenuItem>
                        <MenuItem value={6}>Saturday</MenuItem>
                      </Select>
                    </FormControl>
                    <TextField
                      size="small"
                      label="Start"
                      type="time"
                      value={entry.start}
                      onChange={(e) =>
                        updateScheduleEntry(index, 'start', e.target.value)
                      }
                      InputLabelProps={{ shrink: true }}
                      inputProps={{ step: 300 }}
                    />
                    <TextField
                      size="small"
                      label="End"
                      type="time"
                      value={entry.end}
                      onChange={(e) =>
                        updateScheduleEntry(index, 'end', e.target.value)
                      }
                      InputLabelProps={{ shrink: true }}
                      inputProps={{ step: 300 }}
                    />
                    <IconButton
                      size="small"
                      onClick={() => removeScheduleEntry(index)}
                      color="error"
                    >
                      ×
                    </IconButton>
                  </Box>
                ))}
                {operatingHours.schedule.length === 0 && (
                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    No schedule entries. Booth will be considered always on.
                  </Typography>
                )}
              </Box>
            )}
            {!operatingHours.enabled && (
              <Typography variant="body2" color="text.secondary">
                Operating hours disabled. Booth is expected to be always on.
              </Typography>
            )}
          </DialogContent>
          <DialogActions>
            <Button onClick={() => setEditingHoursBooth(null)}>Cancel</Button>
            <Button type="submit" variant="contained">
              Save
            </Button>
          </DialogActions>
        </form>
      </Dialog>
    </Box>
  );
}

interface BoothRowProps {
  booth: Booth;
  getStatusColor: (
    status: string,
    isStale: boolean,
    isWithinHours: boolean,
  ) => 'error' | 'warning' | 'success' | 'default';
  getStatusLabel: (status: string, isStale: boolean, isWithinHours: boolean) => string;
  onEdit: () => void;
  onEditHours: () => void;
}

function BoothRow({
  booth,
  getStatusColor,
  getStatusLabel,
  onEdit,
  onEditHours,
}: BoothRowProps) {
  const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  
  const operatingHoursText = booth.operatingHours.enabled && booth.operatingHours.schedule.length > 0
    ? booth.operatingHours.schedule.map((entry) => 
        `${dayNames[entry.day]}: ${entry.start}-${entry.end}`
      ).join(', ')
    : 'Always on';

  return (
    <TableRow
      sx={{
        '&:last-child td, &:last-child th': { border: 0 },
        '&:hover': {
          bgcolor: 'action.hover',
        },
      }}
    >
      <TableCell>
        <Typography variant="body2" fontWeight="medium">
          {booth.name || booth.boothId}
        </Typography>
        {booth.message && (
          <Typography variant="caption" color="text.secondary" display="block">
            {booth.message}
          </Typography>
        )}
      </TableCell>
      <TableCell>{booth.boothId}</TableCell>
      <TableCell>
        <Chip
          label={getStatusLabel(booth.status, booth.isStale, booth.isWithinOperatingHours)}
          color={getStatusColor(booth.status, booth.isStale, booth.isWithinOperatingHours)}
          size="small"
        />
      </TableCell>
      <TableCell>{booth.mode}</TableCell>
      <TableCell>{booth.timezone || '-'}</TableCell>
      <TableCell>
        {booth.minutesSinceLastPing < 1
          ? 'Just now'
          : `${booth.minutesSinceLastPing} min ago`}
      </TableCell>
      <TableCell>
        <Typography variant="body2">{operatingHoursText}</Typography>
        {booth.operatingHours.enabled && 
         booth.operatingHours.schedule.length > 0 && 
         !booth.isWithinOperatingHours && (
          <Chip
            label="Offline (Expected)"
            size="small"
            sx={{ mt: 0.5 }}
            color="default"
          />
        )}
      </TableCell>
      <TableCell align="right">
        <Box display="flex" gap={1} justifyContent="flex-end">
          <Button
            startIcon={<EditIcon />}
            onClick={onEdit}
            variant="outlined"
            size="small"
          >
            Edit
          </Button>
          <Button
            startIcon={<ScheduleIcon />}
            onClick={onEditHours}
            variant="outlined"
            size="small"
          >
            Hours
          </Button>
        </Box>
      </TableCell>
    </TableRow>
  );
}
